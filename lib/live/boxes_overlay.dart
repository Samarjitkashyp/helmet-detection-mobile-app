import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'live_detector.dart';

/// Draws the live detection boxes over the camera preview. Box coordinates are relative (0..1) to the frame.
class BoxesPainter extends CustomPainter {
  BoxesPainter(this.boxes);
  final List<LiveBox> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final b in boxes) {
      final color = b.isViolation ? AppColors.danger : AppColors.success;
      final rect = Rect.fromLTRB(b.left * size.width, b.top * size.height, b.right * size.width, b.bottom * size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = color,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${b.isViolation ? 'No helmet' : 'Helmet'} ${(b.confidence * 100).round()}%',
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelTop = (rect.top - tp.height - 4).clamp(0.0, size.height - tp.height - 4);
      final label = Rect.fromLTWH(rect.left.clamp(0.0, size.width - tp.width - 8), labelTop, tp.width + 8, tp.height + 4);
      canvas.drawRRect(RRect.fromRectAndRadius(label, const Radius.circular(4)), Paint()..color = color);
      tp.paint(canvas, Offset(label.left + 4, label.top + 2));
    }
  }

  @override
  bool shouldRepaint(BoxesPainter old) => !identical(old.boxes, boxes);
}
