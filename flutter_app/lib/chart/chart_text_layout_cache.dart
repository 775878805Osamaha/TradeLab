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
  ChartTextLayoutCache({this.capacity = 128, this.pillCapacity = 32,
      this.axisCapacity = 32}) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'Must be positive');
    }
    if (pillCapacity < 1) {
      throw ArgumentError.value(pillCapacity, 'pillCapacity', 'Must be positive');
    }
    if (axisCapacity < 1) {
      throw ArgumentError.value(axisCapacity, 'axisCapacity', 'Must be positive');
    }
  }

  final int capacity;
  /// Selected short-position labels have multiline/width-dependent layout.
  /// Keep their cache separate from price ticks so a large number of changing
  /// axis values cannot evict a stationary stop/target label every frame.
  final int pillCapacity;
  /// Bounded layouts for timezone labels with an explicit ellipsis width.
  /// Time labels without width limits use the ordinary price/text LRU.
  final int axisCapacity;

  final LinkedHashMap<(String, Color, double, FontWeight, bool), TextPainter>
      _painters = LinkedHashMap();
  final LinkedHashMap<(String, double, bool), TextPainter> _pills =
      LinkedHashMap();
  final LinkedHashMap<(String, Color, double, double, bool), TextPainter>
      _boundedAxis = LinkedHashMap();

  int get length => _painters.length;
  int get pillLength => _pills.length;
  int get axisLength => _boundedAxis.length;

  TextPainter layout(String value, Color color, double size, {
    bool bold = false,
    bool rtl = false,
    FontWeight? fontWeight,
  }) {
    // Distinguish the rectangle time tag's normal weight from price tags.
    // Keep previous chart-axis defaults intact (w500 / bold w800).
    final weight = fontWeight ?? (bold ? FontWeight.w800 : FontWeight.w500);
    final key = (value, color, size, weight, rtl);
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
          fontFamily: 'Roboto',
          fontSize: size,
          color: color,
          fontWeight: weight,
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

  /// Timezone labels are constrained and ellipsized on narrow Android
  /// screens. Keep their width-specific layouts separate from regular
  /// axis prices, which are measured without maxWidth or ellipsis.
  TextPainter layoutBoundedAxis(String value, Color color, double size, {
    required double maxWidth,
    bool rtl = true,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      throw ArgumentError.value(maxWidth, 'maxWidth',
          'Must be positive and finite');
    }
    final key = (value, color, size, maxWidth, rtl);
    final reused = _boundedAxis.remove(key);
    if (reused != null) {
      _boundedAxis[key] = reused;
      return reused;
    }
    final painter = TextPainter(
      text: TextSpan(text: value, style: TextStyle(
        fontFamily: 'Roboto',
        color: color, fontSize: size, fontWeight: FontWeight.w500,
      )),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    if (_boundedAxis.length == axisCapacity) {
      _boundedAxis.remove(_boundedAxis.keys.first)?.dispose();
    }
    _boundedAxis[key] = painter;
    return painter;
  }

  /// Reuse exactly measured RTL short-position stop/target/reward labels.
  /// Key includes the plot width and line limit, because resizing/rotating
  /// the phone can change the label wrap and rectangle geometry.
  ///
  /// Formatting matches the original pill painter (centered white 11px
  /// text, height 1.18, one or two lines); only repeated layout is skipped.
  TextPainter layoutPill(String value, {
    required double maxWidth,
    bool twoLines = false,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      throw ArgumentError.value(maxWidth, 'maxWidth', 'Must be positive and finite');
    }
    final key = (value, maxWidth, twoLines);
    final reused = _pills.remove(key);
    if (reused != null) {
      _pills[key] = reused;
      return reused;
    }
    final painter = TextPainter(
      text: TextSpan(text: value, style: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 11, color: Colors.white, height: 1.18)),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
      maxLines: twoLines ? 2 : 1,
    )..layout(maxWidth: maxWidth);
    if (_pills.length == pillCapacity) {
      _pills.remove(_pills.keys.first)?.dispose();
    }
    _pills[key] = painter;
    return painter;
  }

  void clear() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
    for (final painter in _pills.values) {
      painter.dispose();
    }
    _pills.clear();
    for (final painter in _boundedAxis.values) {
      painter.dispose();
    }
    _boundedAxis.clear();
  }
}
