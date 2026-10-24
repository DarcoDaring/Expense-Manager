import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Receipt photos live in the app's private documents folder. Only the file
/// name is stored in the database, because the folder's full path can change
/// between app updates on iOS.
class AttachmentService {
  AttachmentService._();

  static final _picker = ImagePicker();
  static String? _dir;

  /// Attachments need real files, so they are unavailable in the browser.
  static bool get supported => !kIsWeb;

  static Future<void> init() async {
    if (!supported) return;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'attachments'));
    await dir.create(recursive: true);
    _dir = dir.path;
  }

  static File fileFor(String name) => File(p.join(_dir!, name));

  /// Opens the camera or gallery and copies the result into app storage.
  /// Returns the stored file name, or null if the user backed out.
  static Future<String?> pick(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, maxWidth: 1800, imageQuality: 85);
    if (picked == null) return null;
    final ext = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path);
    final name = '${DateTime.now().microsecondsSinceEpoch}$ext';
    await File(picked.path).copy(p.join(_dir!, name));
    return name;
  }

  static Future<void> delete(String? name) async {
    if (!supported || name == null || _dir == null) return;
    try {
      final f = fileFor(name);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // A leftover file is harmless.
    }
  }
}
