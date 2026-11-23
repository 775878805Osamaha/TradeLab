/// Prevents time-axis labels from colliding with one another or with
/// a reserved timezone label in narrow Android layouts.
///
/// This class does not alter market timestamps or candle positions.
class ChartTimeAxisLabelLayout {
  ChartTimeAxisLabelLayout({
    required this.plotWidth,
    this.leftInset = 40,
    this.gap = 6,
  });

  final double plotWidth;
  final double leftInset;
  final double gap;
  final List<(double, double)> _occupied = [];

  /// Reserves an already-measured label. Never clip or silently move candle
  /// timestamps into unrelated axis positions to make a label fit.
  bool reserve({required double left, required double right}) {
    if (!left.isFinite || !right.isFinite || plotWidth <= 0 ||
        left < leftInset || right > plotWidth || right <= left) {
      return false;
    }
    for (final (existingLeft, existingRight) in _occupied) {
      if (left < existingRight + gap && right > existingLeft - gap) {
        return false;
      }
    }
    _occupied.add((left, right));
    return true;
  }

  /// Draw only when the complete measured label fits the available space.
  bool reserveCentered({required double centerX, required double width}) {
    if (!centerX.isFinite || !width.isFinite || width <= 0) {
      return false;
    }
    return reserve(left: centerX - width / 2, right: centerX + width / 2);
  }
}
