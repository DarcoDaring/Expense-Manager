import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../db.dart';
import '../state/app_state.dart';

/// Keeps a copy of all the data in the user's own Google Drive (a hidden
/// app-data file only this app can see) and keeps this phone and that copy
/// in step: changes here are uploaded a few seconds after they are made, and
/// changes made from another install are downloaded.
class SyncService extends ChangeNotifier {
  /// The *Web application* OAuth client ID from Google Cloud Console.
  static const serverClientId = '56581993624-8eoiv9opqiekegu8m2tcajbmlv6tp9ki.apps.googleusercontent.com';

  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _fileName = 'expense_manager_data.json';
  static const _api = 'https://www.googleapis.com';

  /// Whether Google sync can be offered at all on this build.
  static bool get supported => !kIsWeb && serverClientId.isNotEmpty;

  late SharedPreferences _prefs;
  AppState? _state;
  bool _ready = false;

  String? email;
  String? name;
  String? photoUrl;
  DateTime? lastSync;
  String? error;
  bool syncing = false;

  /// The cloud and this phone both hold different data and the user must pick.
  bool conflict = false;

  /// Whether the welcome screen has been dealt with (signed in or skipped).
  bool welcomed = false;

  String? _fileId;
  String? _syncedDigest;
  bool _applying = false;
  Timer? _debounce;
  Timer? _poll;

  bool get signedIn => email != null;

  Future<void> init(AppState state) async {
    _prefs = await SharedPreferences.getInstance();
    welcomed = _prefs.getBool('sync_welcomed') ?? false;
    email = _prefs.getString('sync_email');
    name = _prefs.getString('sync_name');
    photoUrl = _prefs.getString('sync_photo');
    _syncedDigest = _prefs.getString('sync_digest');
    final t = _prefs.getInt('sync_last');
    lastSync = t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
    _state = state;
    if (!supported) return;
    try {
      await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
      if (signedIn) {
        await GoogleSignIn.instance.attemptLightweightAuthentication();
      }
      _ready = true;
    } catch (e) {
      debugPrint('Google sign-in unavailable: $e');
    }
    state.addListener(_onLocalChange);
    if (signedIn) {
      _startPolling();
      unawaited(check());
    }
  }

  Future<void> markWelcomed() async {
    welcomed = true;
    await _prefs.setBool('sync_welcomed', true);
    notifyListeners();
  }

  // ---- sign in / out ----

  /// Signs in and does the first sync. Returns an error message, or null.
  Future<String?> signIn() async {
    if (!_ready) return 'Google sign-in is not set up in this build.';
    try {
      final account = await GoogleSignIn.instance.authenticate(scopeHint: [_scope]);
      // Asks for Drive access (a prompt the first time) while the user is present.
      await account.authorizationClient.authorizeScopes([_scope]);
      email = account.email;
      name = account.displayName;
      photoUrl = account.photoUrl;
      await _prefs.setString('sync_email', email!);
      await _prefs.setString('sync_name', name ?? '');
      await _prefs.setString('sync_photo', photoUrl ?? '');
      await markWelcomed();
      error = null;
      notifyListeners();
      await _firstSync();
      _startPolling();
      return null;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return 'Sign-in cancelled';
      return 'Could not sign in (${e.code.name})';
    } catch (e) {
      return 'Could not sign in: $e';
    }
  }

  Future<void> signOut() async {
    _poll?.cancel();
    _debounce?.cancel();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    email = name = photoUrl = null;
    lastSync = null;
    _fileId = null;
    _syncedDigest = null;
    conflict = false;
    error = null;
    for (final k in ['sync_email', 'sync_name', 'sync_photo', 'sync_digest', 'sync_last']) {
      await _prefs.remove(k);
    }
    notifyListeners();
  }

  // ---- when to sync ----

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 90), (_) => check());
  }

  void _onLocalChange() {
    if (!signedIn || _applying || conflict) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), check);
  }

  /// Called when the app comes back to the foreground.
  Future<void> onResume() async {
    if (signedIn) await check();
  }

  /// Brings this phone and the cloud copy in step, whichever side changed.
  Future<void> check() async {
    if (!signedIn || !_ready || syncing || conflict) return;
    await _run(() async {
      final token = await _token();
      final remote = await _remote(token);
      final local = await _localDigest();
      final r = remote?.digest;
      if (r == null) {
        await _push(token, local);
      } else if (r == local) {
        await _markSynced(local);
      } else if (local == _syncedDigest) {
        await _pull(token, remote!);
      } else if (r == _syncedDigest) {
        await _push(token, local);
      } else {
        conflict = true;
      }
    });
  }

  Future<void> _firstSync() async {
    await _run(() async {
      final token = await _token();
      final remote = await _remote(token);
      final local = await _localDigest();
      if (remote == null) {
        await _push(token, local);
      } else if (remote.digest == local) {
        await _markSynced(local);
      } else if (await _localIsEmpty()) {
        await _pull(token, remote);
      } else {
        conflict = true;
      }
    });
  }

  /// Resolves [conflict]: keep the cloud copy or keep this phone's data.
  Future<void> resolve({required bool useCloud}) async {
    conflict = false;
    await _run(() async {
      final token = await _token();
      final remote = await _remote(token);
      if (useCloud && remote != null) {
        await _pull(token, remote);
      } else {
        await _push(token, await _localDigest());
      }
    });
  }

  /// Uploads this phone's data now.
  Future<void> backupNow() async {
    if (!signedIn || !_ready) return;
    await _run(() async => _push(await _token(), await _localDigest()));
  }

  Future<void> _run(Future<void> Function() job) async {
    if (syncing) return;
    syncing = true;
    error = null;
    notifyListeners();
    try {
      await job();
    } catch (e) {
      debugPrint('Sync failed: $e');
      error = e is _AuthLost ? 'Please sign in again to keep syncing' : 'Could not sync. Will retry.';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  // ---- data ----

  Future<Map<String, List<Map<String, Object?>>>> _local() => AppDb.instance.exportAll();

  String _digestOf(Object data) => sha256.convert(utf8.encode(jsonEncode(data))).toString();

  Future<String> _localDigest() async => _digestOf(await _local());

  Future<bool> _localIsEmpty() async {
    final d = await _local();
    return ['expenses', 'incomes', 'recurring', 'notes', 'card_payments']
        .every((t) => (d[t] ?? const []).isEmpty);
  }

  Future<void> _markSynced(String digest) async {
    _syncedDigest = digest;
    lastSync = DateTime.now();
    await _prefs.setString('sync_digest', digest);
    await _prefs.setInt('sync_last', lastSync!.millisecondsSinceEpoch);
  }

  Future<void> _push(String token, String digest) async {
    final body = jsonEncode({'version': 1, 'data': await _local()});
    final meta = {
      if (_fileId == null) 'name': _fileName,
      if (_fileId == null) 'parents': ['appDataFolder'],
      'appProperties': {'digest': digest},
    };
    const boundary = 'em_sync_boundary';
    final multipart = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode(meta)}\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$body\r\n'
        '--$boundary--';
    final uri = _fileId == null
        ? Uri.parse('$_api/upload/drive/v3/files?uploadType=multipart&fields=id')
        : Uri.parse('$_api/upload/drive/v3/files/$_fileId?uploadType=multipart&fields=id');
    final req = http.Request(_fileId == null ? 'POST' : 'PATCH', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'multipart/related; boundary=$boundary'
      ..bodyBytes = utf8.encode(multipart);
    final res = await http.Response.fromStream(await req.send());
    _check(res);
    _fileId ??= (jsonDecode(res.body) as Map)['id'] as String?;
    await _markSynced(digest);
  }

  Future<void> _pull(String token, _Remote remote) async {
    final res = await http.get(
      Uri.parse('$_api/drive/v3/files/${remote.id}?alt=media'),
      headers: {'Authorization': 'Bearer $token'},
    );
    _check(res);
    final raw = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['data'] as Map;
    final data = {
      for (final e in raw.entries)
        e.key as String: [
          for (final row in e.value as List) Map<String, Object?>.from(row as Map)
        ]
    };
    _applying = true;
    try {
      await AppDb.instance.importAll(data);
      await _state?.reload();
    } finally {
      _applying = false;
    }
    await _markSynced(await _localDigest());
  }

  // ---- Drive ----

  Future<_Remote?> _remote(String token) async {
    final q = Uri.encodeQueryComponent("name='$_fileName'");
    final res = await http.get(
      Uri.parse('$_api/drive/v3/files?spaces=appDataFolder&q=$q'
          '&fields=files(id,appProperties)'),
      headers: {'Authorization': 'Bearer $token'},
    );
    _check(res);
    final files = (jsonDecode(res.body) as Map)['files'] as List;
    if (files.isEmpty) {
      _fileId = null;
      return null;
    }
    final f = files.first as Map;
    _fileId = f['id'] as String;
    final props = f['appProperties'] as Map?;
    return _Remote(_fileId!, props?['digest'] as String?);
  }

  void _check(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) throw _AuthLost();
    if (res.statusCode >= 300) throw 'Drive error ${res.statusCode}: ${res.body}';
  }

  Future<String> _token() async {
    final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) throw _AuthLost();
    final auth = await account.authorizationClient.authorizationForScopes([_scope]);
    if (auth == null) throw _AuthLost();
    return auth.accessToken;
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _state?.removeListener(_onLocalChange);
    super.dispose();
  }
}

class _Remote {
  final String id;
  final String? digest;
  _Remote(this.id, this.digest);
}

class _AuthLost implements Exception {}
