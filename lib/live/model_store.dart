import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';

class LiveModel {
  const LiveModel(this.file, this.imgsz);
  final File file;
  final int imgsz;
}

/// Keeps the on-device detection model up to date. The model lives on the server (not inside the APK), so a
/// retrained model reaches phones without a new app release; it is downloaded once and re-checked on each use.
class LiveModelStore {
  static const _versionKey = 'live_model_version';
  static const _imgszKey = 'live_model_imgsz';

  /// Returns the model ready to load, or null if it is not available (offline and never downloaded).
  static Future<LiveModel?> ensure(Api api, SharedPreferences prefs, void Function(double) onProgress) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/live');
    await dir.create(recursive: true);
    final file = File('${dir.path}/live.onnx');

    final cachedVersion = prefs.getString(_versionKey);
    final cachedImgsz = prefs.getInt(_imgszKey) ?? 416;
    final haveCached = file.existsSync() && cachedVersion != null;

    Map<String, dynamic>? info;
    try {
      info = await api.liveModelInfo();
    } on ApiException {
      info = null; // offline or not published: fall back to what we already have
    }
    if (info == null) return haveCached ? LiveModel(file, cachedImgsz) : null;

    final size = (info['size'] as num).toInt();
    final imgsz = (info['imgsz'] as num).toInt();
    if (haveCached && cachedVersion == info['version'] && file.lengthSync() == size) {
      return LiveModel(file, imgsz);
    }

    final part = File('${file.path}.part');
    try {
      await api.downloadFile('/app/live-model', part.path, onProgress);
    } on ApiException {
      if (part.existsSync()) part.deleteSync();
      return haveCached ? LiveModel(file, cachedImgsz) : null;
    }
    if (part.lengthSync() != size) {
      part.deleteSync();
      return haveCached ? LiveModel(file, cachedImgsz) : null;
    }
    if (file.existsSync()) file.deleteSync();
    part.renameSync(file.path);
    await prefs.setString(_versionKey, info['version'] as String);
    await prefs.setInt(_imgszKey, imgsz);
    return LiveModel(file, imgsz);
  }
}
