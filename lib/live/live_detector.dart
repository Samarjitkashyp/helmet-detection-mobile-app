import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:onnxruntime/onnxruntime.dart';

/// One camera frame in YUV 4:2:0 layout (what Android cameras deliver), independent of the camera plugin
/// so the maths below can be unit-tested.
class YuvFrame {
  YuvFrame({
    required this.width,
    required this.height,
    required this.y,
    required this.u,
    required this.v,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
  });

  final int width;
  final int height;
  final Uint8List y;
  final Uint8List u;
  final Uint8List v;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;

  /// Returns null when the camera does not deliver 3-plane YUV (live boxes are then unavailable).
  static YuvFrame? fromCameraImage(CameraImage image) {
    if (image.format.group != ImageFormatGroup.yuv420 || image.planes.length != 3) return null;
    final p = image.planes;
    return YuvFrame(
      width: image.width,
      height: image.height,
      y: p[0].bytes,
      u: p[1].bytes,
      v: p[2].bytes,
      yRowStride: p[0].bytesPerRow,
      uvRowStride: p[1].bytesPerRow,
      uvPixelStride: p[1].bytesPerPixel ?? 1,
    );
  }
}

/// How the upright frame sits inside the square model input.
class Letterbox {
  Letterbox(this.uprightWidth, this.uprightHeight, this.size)
      : scale = size / max(uprightWidth, uprightHeight) {
    contentWidth = (uprightWidth * scale).round();
    contentHeight = (uprightHeight * scale).round();
    left = (size - contentWidth) ~/ 2;
    top = (size - contentHeight) ~/ 2;
  }

  final int uprightWidth;
  final int uprightHeight;
  final int size;
  final double scale;
  late final int contentWidth;
  late final int contentHeight;
  late final int left;
  late final int top;
}

/// A detection in coordinates relative to the upright frame (0..1), ready to draw over the preview.
class LiveBox {
  const LiveBox(this.classId, this.confidence, this.left, this.top, this.right, this.bottom);
  final int classId; // 0 = helmet, 1 = no_helmet
  final double confidence;
  final double left, top, right, bottom;

  bool get isViolation => classId == 1;
  double get height => bottom - top;
}

/// Pure helpers: frame -> model input, model output -> boxes.
class LiveMath {
  static const int padValue = 114;

  /// Clockwise turn (0/90/180/270) that makes a camera frame upright on a screen shown in [ui] orientation.
  /// Android: (sensorOrientation - displayRotation + 360) % 360 for back cameras, where the display rotation is
  /// how far the phone is turned counter-clockwise from portrait (landscapeLeft = 90).
  static int uprightRotation(int sensorOrientation, DeviceOrientation ui) {
    final ccw = switch (ui) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    return (sensorOrientation - ccw + 360) % 360;
  }

  /// Builds the CHW float tensor (RGB, 0..1) for the model. [rotation] is the clockwise turn (0/90/180/270)
  /// that makes the sensor image upright. Each model pixel averages 2x2 source samples to avoid aliasing.
  static (Float32List, Letterbox) buildInput(YuvFrame f, int rotation, int size) {
    final rotated = rotation == 90 || rotation == 270;
    final lb = Letterbox(rotated ? f.height : f.width, rotated ? f.width : f.height, size);
    final plane = size * size;
    final out = Float32List(3 * plane)..fillRange(0, 3 * plane, padValue / 255.0);

    final uw = lb.uprightWidth, uh = lb.uprightHeight;
    final inv = 1.0 / lb.scale;
    const offsets = [0.25, 0.75];

    for (var ty = lb.top; ty < lb.top + lb.contentHeight; ty++) {
      for (var tx = lb.left; tx < lb.left + lb.contentWidth; tx++) {
        var r = 0.0, g = 0.0, b = 0.0;
        for (final oy in offsets) {
          final uy = min(uh - 1, ((ty - lb.top + oy) * inv).floor());
          for (final ox in offsets) {
            final ux = min(uw - 1, ((tx - lb.left + ox) * inv).floor());
            final int sx, sy;
            switch (rotation) {
              case 90:
                sx = uy;
                sy = f.height - 1 - ux;
              case 180:
                sx = f.width - 1 - ux;
                sy = f.height - 1 - uy;
              case 270:
                sx = f.width - 1 - uy;
                sy = ux;
              default:
                sx = ux;
                sy = uy;
            }
            final yy = f.y[sy * f.yRowStride + sx].toDouble();
            final uvIndex = (sy >> 1) * f.uvRowStride + (sx >> 1) * f.uvPixelStride;
            final uu = f.u[uvIndex] - 128.0;
            final vv = f.v[uvIndex] - 128.0;
            r += yy + 1.402 * vv;
            g += yy - 0.344136 * uu - 0.714136 * vv;
            b += yy + 1.772 * uu;
          }
        }
        final i = ty * size + tx;
        out[i] = (r * 0.25).clamp(0.0, 255.0) / 255.0;
        out[plane + i] = (g * 0.25).clamp(0.0, 255.0) / 255.0;
        out[2 * plane + i] = (b * 0.25).clamp(0.0, 255.0) / 255.0;
      }
    }
    return (out, lb);
  }

  /// Decodes the YOLOv8 head output laid out as [4 box rows + classCount score rows] x [n candidates].
  static List<LiveBox> decode(Float32List out, int n, Letterbox lb,
      {int classCount = 2, double confThreshold = 0.4, double nmsIou = 0.45}) {
    final cands = <LiveBox>[];
    for (var i = 0; i < n; i++) {
      var best = 0, bestScore = out[4 * n + i];
      for (var c = 1; c < classCount; c++) {
        final s = out[(4 + c) * n + i];
        if (s > bestScore) {
          bestScore = s;
          best = c;
        }
      }
      if (bestScore < confThreshold) continue;
      final cx = out[i], cy = out[n + i], w = out[2 * n + i], h = out[3 * n + i];
      double toX(double v) => ((v - lb.left) / lb.scale / lb.uprightWidth).clamp(0.0, 1.0);
      double toY(double v) => ((v - lb.top) / lb.scale / lb.uprightHeight).clamp(0.0, 1.0);
      final box = LiveBox(best, bestScore, toX(cx - w / 2), toY(cy - h / 2), toX(cx + w / 2), toY(cy + h / 2));
      if (box.right > box.left && box.bottom > box.top) cands.add(box);
    }
    return nms(cands, nmsIou);
  }

  static List<LiveBox> nms(List<LiveBox> boxes, double iouThreshold) {
    boxes.sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <LiveBox>[];
    for (final b in boxes) {
      if (kept.every((k) => iou(k, b) <= iouThreshold)) kept.add(b);
    }
    return kept;
  }

  static double iou(LiveBox a, LiveBox b) {
    final ix = max(0.0, min(a.right, b.right) - max(a.left, b.left));
    final iy = max(0.0, min(a.bottom, b.bottom) - max(a.top, b.top));
    final inter = ix * iy;
    final union = (a.right - a.left) * (a.bottom - a.top) + (b.right - b.left) * (b.bottom - b.top) - inter;
    return union <= 0 ? 0 : inter / union;
  }
}

/// Runs the downloaded ONNX model on camera frames.
class LiveDetector {
  LiveDetector._(this._session, this._inputName, this.imgsz);

  final OrtSession _session;
  final String _inputName;
  final int imgsz;

  static bool _envReady = false;

  static Future<LiveDetector> load(File modelFile, int imgsz) async {
    if (!_envReady) {
      OrtEnv.instance.init();
      _envReady = true;
    }
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(4)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    final session = OrtSession.fromFile(modelFile, options);
    options.release();
    return LiveDetector._(session, session.inputNames.first, imgsz);
  }

  Future<List<LiveBox>> detect(YuvFrame frame, int rotation) async {
    final (input, lb) = LiveMath.buildInput(frame, rotation, imgsz);
    final tensor = OrtValueTensor.createTensorWithDataList(input, [1, 3, imgsz, imgsz]);
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      outputs = await _session.runAsync(runOptions, {_inputName: tensor});
      final value = outputs?.first?.value; // [1][rows][n]
      if (value is! List || value.isEmpty) return const [];
      final rows = value.first as List;
      final n = (rows.first as List).length;
      final flat = Float32List(rows.length * n);
      for (var r = 0; r < rows.length; r++) {
        final row = rows[r] as List;
        for (var i = 0; i < n; i++) {
          flat[r * n + i] = (row[i] as num).toDouble();
        }
      }
      return LiveMath.decode(flat, n, lb, classCount: rows.length - 4);
    } finally {
      tensor.release();
      runOptions.release();
      outputs?.forEach((o) => o?.release());
    }
  }

  void dispose() => _session.release();
}
