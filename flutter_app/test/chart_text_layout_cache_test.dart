import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/chart_text_layout_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('repaint reuses the exact measured price label without relayout', () {
    final cache = ChartTextLayoutCache();
    addTearDown(cache.clear);
    final first = cache.layout('3,987.50', Colors.white, 12);
    final second = cache.layout('3,987.50', Colors.white, 12);
    expect(identical(first, second), isTrue);
    expect(first.width, greaterThan(0));
    expect(second.width, first.width);
    expect(cache.length, 1);
  });

  test('color, font size, weight and RTL are part of cache identity', () {
    final cache = ChartTextLayoutCache();
    addTearDown(cache.clear);
    final normal = cache.layout('3988', Colors.white, 12);
    final dark = cache.layout('3988', Colors.black, 12);
    final large = cache.layout('3988', Colors.white, 14);
    final bold = cache.layout('3988', Colors.white, 12, bold: true);
    final arabic = cache.layout('3988', Colors.white, 12, rtl: true);
    expect(cache.length, 5);
    expect(identical(normal, dark), isFalse);
    expect(identical(normal, large), isFalse);
    expect(identical(normal, bold), isFalse);
    expect(identical(normal, arabic), isFalse);
  });

  test('bounded LRU evicts the oldest label and keeps recently used price', () {
    final cache = ChartTextLayoutCache(capacity: 2);
    addTearDown(cache.clear);
    final original = cache.layout('100', Colors.white, 12);
    final older = cache.layout('101', Colors.white, 12);
    expect(identical(cache.layout('100', Colors.white, 12), original), isTrue);
    cache.layout('102', Colors.white, 12);
    expect(cache.length, 2);
    expect(older.debugDisposed, isTrue);
    expect(original.debugDisposed, isFalse);
    expect(identical(cache.layout('100', Colors.white, 12), original), isTrue);
  });

  test('clear releases measured paragraphs when chart state is disposed', () {
    final cache = ChartTextLayoutCache();
    final painter = cache.layout('99.9', Colors.white, 11);
    cache.clear();
    expect(cache.length, 0);
    expect(painter.debugDisposed, isTrue);
  });

  test('invalid cache capacity fails without allocating a layout', () {
    expect(() => ChartTextLayoutCache(capacity: 0), throwsArgumentError);
  });
}
