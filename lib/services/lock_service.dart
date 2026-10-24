import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the app-lock settings (PIN + optional biometrics) and the
/// locked/unlocked state of the current session.
class LockService extends ChangeNotifier {
  static const _kEnabled = 'lock_enabled';
  static const _kBio = 'lock_biometric';
  static const _kPin = 'lock_pin_hash';
  static const _kSalt = 'lock_pin_salt';
  static const pinLength = 4;

  final _secure = const FlutterSecureStorage();
  final _auth = LocalAuthentication();

  bool enabled = false;
  bool biometricEnabled = false;
  bool biometricAvailable = false;
  bool locked = false;
  bool ready = false;

  /// True while the system biometric sheet is up, so the resulting
  /// lifecycle pause/resume does not re-lock the app.
  bool authenticating = false;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_kEnabled) ?? false;
    biometricEnabled = prefs.getBool(_kBio) ?? false;
    // Guard against a wiped keystore: a lock without a PIN would be unusable.
    if (enabled && await _readPin() == null) {
      enabled = false;
      biometricEnabled = false;
      await prefs.setBool(_kEnabled, false);
      await prefs.setBool(_kBio, false);
    }
    await refreshBiometricAvailability();
    locked = enabled;
    ready = true;
    notifyListeners();
  }

  Future<String?> _readPin() async {
    try {
      return await _secure.read(key: _kPin);
    } catch (_) {
      return null; // unreadable keystore entry: treat as no PIN set
    }
  }

  Future<void> refreshBiometricAvailability() async {
    if (kIsWeb) {
      biometricAvailable = false; // local_auth has no web support
      return;
    }
    try {
      biometricAvailable =
          await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      biometricAvailable = false;
    }
  }

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> setPin(String pin) async {
    final salt = base64UrlEncode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    await _secure.write(key: _kSalt, value: salt);
    await _secure.write(key: _kPin, value: _hash(pin, salt));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, true);
    enabled = true;
    notifyListeners();
  }

  Future<bool> verifyPin(String pin) async {
    final salt = await _secure.read(key: _kSalt);
    final stored = await _secure.read(key: _kPin);
    if (salt == null || stored == null) return false;
    return _hash(pin, salt) == stored;
  }

  /// Returns true and unlocks if the PIN is right.
  Future<bool> unlockWithPin(String pin) async {
    if (!await verifyPin(pin)) return false;
    locked = false;
    notifyListeners();
    return true;
  }

  Future<bool> _promptBiometric(String reason) async {
    authenticating = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    } finally {
      // Let the resume event that follows the sheet closing pass first.
      Future.delayed(const Duration(milliseconds: 500), () => authenticating = false);
    }
  }

  Future<bool> unlockWithBiometric() async {
    if (!enabled || !biometricEnabled) return false;
    if (!await _promptBiometric('Unlock Expense Manager')) return false;
    locked = false;
    notifyListeners();
    return true;
  }

  /// A biometric check that leaves the lock state alone, used to confirm that
  /// it is really the owner before showing something private.
  Future<bool> confirmWithBiometric(String reason) =>
      enabled && biometricEnabled ? _promptBiometric(reason) : Future.value(false);

  /// The phone's own screen lock or biometrics, for when no app PIN is set.
  /// Returns null when this phone has nothing to check against.
  Future<bool?> confirmWithDevice(String reason) async {
    if (kIsWeb) return null;
    try {
      if (!await _auth.isDeviceSupported()) return null;
    } catch (_) {
      return null;
    }
    authenticating = true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    } on PlatformException {
      return false;
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () => authenticating = false);
    }
  }

  /// Turns biometrics on only after one successful scan proves it works.
  Future<bool> enableBiometric() async {
    await refreshBiometricAvailability();
    if (!biometricAvailable) return false;
    if (!await _promptBiometric('Confirm to enable biometric unlock')) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBio, true);
    biometricEnabled = true;
    notifyListeners();
    return true;
  }

  Future<void> disableBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBio, false);
    biometricEnabled = false;
    notifyListeners();
  }

  Future<void> disableLock() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, false);
    await prefs.setBool(_kBio, false);
    await _secure.delete(key: _kPin);
    await _secure.delete(key: _kSalt);
    enabled = false;
    biometricEnabled = false;
    locked = false;
    notifyListeners();
  }

  void lock() {
    if (enabled && !locked && !authenticating) {
      locked = true;
      notifyListeners();
    }
  }
}
