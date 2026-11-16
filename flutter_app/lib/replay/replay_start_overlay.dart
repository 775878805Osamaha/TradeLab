import 'package:flutter/material.dart';

/// A purely visual reference to the selected historical bar. Touch and
/// timestamps are owned by ChartScreen/ReplayStartResolver, not this painter.
class ReplayStartOverlayPainter extends CustomPainter {
  const ReplayStartOverlayPainter({
    required this.cursorX,
    required this.plotWidth,
    required this.dark,
  });

  final double cursorX;
  final double plotWidth;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final width = plotWidth.clamp(0.0, size.width).toDouble();
    if (!cursorX.isFinite || width < 1) return;
    // Offscreen historical selection must NOT appear falsely pinned to an
    // edge while the user pans/zooms to a different point in the timeline.
    final x = cursorX.clamp(0.0, width).toDouble();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, width, size.height));
    // Future remains visible ONLY during the choosing stage and is clearly
    // muted. Once confirmed, ChartScreen renders a strict source prefix.
    canvas.drawRect(
      Rect.fromLTWH(x, 0, width - x, size.height),
      Paint()..color = (dark ? Colors.black : Colors.white)
          .withValues(alpha: .70),
    );
    if (cursorX >= 0 && cursorX <= width) {
      canvas.drawLine(Offset(cursorX, 0), Offset(cursorX, size.height),
        Paint()
          ..color = const Color(0xFF2962FF)
          ..strokeWidth = 2.7
          ..isAntiAlias = true);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ReplayStartOverlayPainter old) =>
      old.cursorX != cursorX || old.plotWidth != plotWidth ||
      old.dark != dark;
}
