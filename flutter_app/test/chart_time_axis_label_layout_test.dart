import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_time_axis_label_layout.dart';

void main() {
  test('phone time axis never collides with drawing rail or timezone', () {
    final labels = ChartTimeAxisLabelLayout(plotWidth: 330, gap: 8);
    expect(labels.reserve(left: 215, right: 326), isTrue,
        reason: 'The timezone occupies the measured rightmost strip');

    expect(labels.reserveCentered(centerX: 65, width: 60), isFalse,
        reason: 'Leftmost time must not paint under the drawing rail');
    expect(labels.reserveCentered(centerX: 165, width: 55), isTrue,
        reason: 'A timestamp can paint when fully visible');
    expect(labels.reserveCentered(centerX: 230, width: 50), isFalse,
        reason: 'A timestamp cannot paint through the timezone');
    expect(labels.reserveCentered(centerX: 196, width: 28), isFalse,
        reason: 'A timestamp cannot collide with the accepted label');
  });

  test('narrow screens skip labels rather than clipping time text', () {
    final labels = ChartTimeAxisLabelLayout(plotWidth: 175, gap: 6);
    expect(labels.reserve(left: 125, right: 172), isTrue);
    expect(labels.reserveCentered(centerX: 60, width: 50), isFalse);
    expect(labels.reserveCentered(centerX: 90, width: 38), isTrue);
    expect(labels.reserveCentered(centerX: 130, width: 32), isFalse);
  });

  test('non-finite, clipped and zero width geometry is rejected', () {
    final labels = ChartTimeAxisLabelLayout(plotWidth: 320);
    expect(labels.reserveCentered(centerX: double.nan, width: 30), isFalse);
    expect(labels.reserveCentered(centerX: 160, width: 0), isFalse);
    expect(labels.reserve(left: 20, right: 100), isFalse);
    expect(labels.reserve(left: 270, right: 324), isFalse);
    expect(labels.reserve(left: 100, right: 100), isFalse);
    expect(labels.reserveCentered(centerX: 160, width: 60), isTrue);
  });

  test('timezone and time labels share one collision-aware layout', () {
    final labels = ChartTimeAxisLabelLayout(plotWidth: 560);
    expect(labels.reserve(left: 444, right: 557), isTrue);
    expect(labels.reserveCentered(centerX: 112, width: 71), isTrue);
    expect(labels.reserveCentered(centerX: 224, width: 71), isTrue);
    expect(labels.reserveCentered(centerX: 336, width: 71), isTrue);
    expect(labels.reserveCentered(centerX: 448, width: 71), isFalse);
  });
}
