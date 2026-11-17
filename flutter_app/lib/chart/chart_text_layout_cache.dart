import 'dart:collection';

import 'package:flutter/material.dart';

/// Reuses measured chart-axis text paragraphs between paint-only gesture
/// frames. A pan/pinch invalidates the candle canvas but must not layout the
/// exact same price labels again and again.
///
/// Layout identity includes color, font size/weight and reading direction;
/// a theme or axis-settings change cannot reuse a mismatched paragraph.
/// This is an LRU with a strict bound, never an unbounded per-price cache.
class ChartTextLayoutCache {
  ChartTextLayoutCache({this.capacity = 128}) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive');
    }
  }

  final int capacity;

  final LinkedHashMap<(String, Color, double, bool, bool), TextPainter>
      _painters = LinkedHashMap();

  int get length => _painters.length;

  TextPainter layout(String value, Color color, double size, {
    bool bold = false,
    bool rtl = false,
  }) {
    final key = (value, color, size, bold, rtl);
    final reused = _painters.remove(key);
    if (reused != null) {
      // Promote the most recently used label to the back of the LRU.
      _painters[key] = reused;
      return reused;
    }

    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      maxLines: 1,
    )..layout();
    if (_painters.length == capacity) {
      _painters.remove(_painters.keys.first)?.dispose();
    }
    _painters[key] = painter;
    return painter;
  }

  void paint(Canvas canvas, String value, Offset offset, Color color,
      double size, {bool bold = false, bool rtl = false}) {
    layout(value, color, size, bold: bold, rtl: rtl).paint(canvas, offset);
  }

  void clear() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }
}
