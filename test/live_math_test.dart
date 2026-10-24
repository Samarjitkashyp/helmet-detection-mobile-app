import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmet_app/live/live_detector.dart';

/// Source frame whose luma encodes its position: y = 10 * row + col. Chroma is neutral, so R = G = B = luma.
YuvFrame _frame(int w, int h, {int uvPixelStride = 1}) {
  final y = Uint8List(w * h);
  for (var r = 0; r < h; r++) {
    for (var c = 0; c < w; c++) {
      y[r * w + c] = 10 * r + c;
    }
  }
  final uvW = w ~/ 2, uvH = h ~/ 2;
  final rowStride = uvW * uvPixelStride;
  final u = Uint8List(rowStride * uvH)..fillRange(0, rowStride * uvH, 128);
  final v = Uint8List(rowStride * uvH)..fillRange(0, rowStride * uvH, 128);
  return YuvFrame(
      width: w, height: h, y: y, u: u, v: v, yRowStride: w, uvRowStride: rowStride, uvPixelStride: uvPixelStride);
}

/// Rotates a matrix 90 degrees clockwise (independent of the index formulas used by the app).
List<List<int>> _rotateCw(List<List<int>> m) {
  final h = m.length, w = m[0].length;
  return List.generate(w, (r) => List.generate(h, (c) => m[h - 1 - c][r]));
}

void main() {
  group('buildInput', () {
    for (final rotation in [0, 90, 180, 270]) {
      test('rotation $rotation puts every source pixel in the right upright place', () {
        const w = 4, h = 2;
        final f = _frame(w, h);
        var expected = List.generate(h, (r) => List.generate(w, (c) => 10 * r + c));
        for (var i = 0; i < rotation ~/ 90; i++) {
          expected = _rotateCw(expected);
        }
        final uh = expected.length, uw = expected[0].length;

        final (tensor, lb) = LiveMath.buildInput(f, rotation, 8);
        expect(lb.uprightWidth, uw);
        expect(lb.uprightHeight, uh);
        const plane = 8 * 8;
        for (var uy = 0; uy < uh; uy++) {
          for (var ux = 0; ux < uw; ux++) {
            // centre of the model pixels that cover this upright pixel
            final tx = lb.left + ((ux + 0.5) * lb.scale).floor();
            final ty = lb.top + ((uy + 0.5) * lb.scale).floor();
            final value = tensor[ty * 8 + tx] * 255;
            expect(value, closeTo(expected[uy][ux].toDouble(), 0.6), reason: 'upright ($ux,$uy)');
            expect(tensor[plane + ty * 8 + tx] * 255, closeTo(value, 0.6)); // G equals R for neutral chroma
          }
        }
      });
    }

    test('padding is grey 114 and the content is centred', () {
      final f = _frame(4, 2); // upright after 90 deg: 2 wide x 4 tall
      final (tensor, lb) = LiveMath.buildInput(f, 90, 8);
      expect(lb.left, 2);
      expect(lb.top, 0);
      expect(tensor[0] * 255, closeTo(114, 0.01)); // top-left corner is padding
    });

    test('interleaved chroma (pixel stride 2, as many Android phones deliver) gives the same result', () {
      final a = LiveMath.buildInput(_frame(4, 4), 90, 8).$1;
      final b = LiveMath.buildInput(_frame(4, 4, uvPixelStride: 2), 90, 8).$1;
      expect(b, orderedEquals(a));
    });

    test('colour: strong red chroma gives high R, low B', () {
      final f = _frame(4, 4);
      f.u.fillRange(0, f.u.length, 90);
      f.v.fillRange(0, f.v.length, 240);
      final (tensor, lb) = LiveMath.buildInput(f, 0, 8);
      final i = lb.top * 8 + lb.left;
      expect(tensor[i], greaterThan(tensor[2 * 64 + i]));
    });
  });

  group('decode', () {
    // 3 candidates, 2 classes. Layout: rows cx, cy, w, h, score0, score1, each of length 3.
    Float32List out(List<List<double>> rows) => Float32List.fromList([for (final r in rows) ...r]);

    test('maps model coordinates back to the upright frame and picks the best class', () {
      final lb = Letterbox(200, 100, 100); // scale 0.5, content 100x50, left 0, top 25
      final o = out([
        [50, 0, 0], // cx
        [50, 0, 0], // cy
        [20, 0, 0], // w
        [10, 0, 0], // h
        [0.2, 0, 0], // helmet score
        [0.9, 0, 0], // no_helmet score
      ]);
      final boxes = LiveMath.decode(o, 3, lb);
      expect(boxes, hasLength(1));
      final b = boxes.single;
      expect(b.classId, 1);
      expect(b.isViolation, isTrue);
      expect(b.confidence, closeTo(0.9, 1e-6));
      // x: (50-10-0)/0.5/200 = 0.4 .. (50+10)/0.5/200 = 0.6 ; y: (50-5-25)/0.5/100 = 0.4 .. (50+5-25)/0.5/100 = 0.6
      expect(b.left, closeTo(0.4, 1e-6));
      expect(b.right, closeTo(0.6, 1e-6));
      expect(b.top, closeTo(0.4, 1e-6));
      expect(b.bottom, closeTo(0.6, 1e-6));
    });

    test('drops low-confidence candidates and suppresses overlapping duplicates', () {
      final lb = Letterbox(100, 100, 100);
      final o = out([
        [50, 52, 10], // cx
        [50, 51, 90], // cy
        [20, 20, 10], // w
        [20, 20, 10], // h
        [0.9, 0.6, 0.1], // helmet
        [0.0, 0.0, 0.2], // no_helmet
      ]);
      final boxes = LiveMath.decode(o, 3, lb);
      expect(boxes, hasLength(1)); // 2nd overlaps the 1st (suppressed), 3rd is below 0.4
      expect(boxes.single.confidence, closeTo(0.9, 1e-6));
    });

    test('keeps two separate people', () {
      final lb = Letterbox(100, 100, 100);
      final o = out([
        [20, 80],
        [50, 50],
        [20, 20],
        [20, 20],
        [0.9, 0.8],
        [0.0, 0.0],
      ]);
      expect(LiveMath.decode(o, 2, lb), hasLength(2));
    });
  });
}
