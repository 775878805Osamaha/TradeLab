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

  test('selected short-position pills reuse identical RTL measured layouts',
      () {
    final cache = ChartTextLayoutCache();
    addTearDown(cache.clear);
    const caption = 'الهدف: 3,987.50 (1.500%)';
    final one = cache.layoutPill(caption, maxWidth: 240);
    final repeated = cache.layoutPill(caption, maxWidth: 240);
    expect(identical(one, repeated), isTrue);
    expect(cache.pillLength, 1);
    expect(one.width, greaterThan(0));
    expect(one.textDirection, TextDirection.rtl);
    expect(one.textAlign, TextAlign.center);
    expect(one.maxLines, 1);
    final style = (one.text! as TextSpan).style!;
    expect(style.fontSize, 11);
    expect(style.color, Colors.white);
    expect(style.height, 1.18);
  });

  test('resizing chart and changing line count never reuse stale pill geometry',
      () {
    final cache = ChartTextLayoutCache();
    addTearDown(cache.clear);
    const text = 'العائد المحتمل 50 نسبة العائد/المخاطرة 2.0';
    final original = cache.layoutPill(text, maxWidth: 240);
    final narrower = cache.layoutPill(text, maxWidth: 100);
    final twoLines = cache.layoutPill(text, maxWidth: 100, twoLines: true);
    final different = cache.layoutPill('الإيقاف 99', maxWidth: 240);
    expect(cache.pillLength, 4);
    expect(identical(original, narrower), isFalse);
    expect(identical(narrower, twoLines), isFalse);
    expect(identical(original, different), isFalse);
    expect(twoLines.maxLines, 2);
  });

  test('bounded pill LRU evicts old paragraphs and clears all resources',
      () {
    final cache = ChartTextLayoutCache(capacity: 2, pillCapacity: 2);
    final price = cache.layout('3987', Colors.black, 12);
    final stop = cache.layoutPill('إيقاف', maxWidth: 150);
    final target = cache.layoutPill('هدف', maxWidth: 150);
    expect(identical(cache.layoutPill('إيقاف', maxWidth: 150), stop), isTrue);
    cache.layoutPill('عائد', maxWidth: 150);
    expect(cache.pillLength, 2);
    expect(target.debugDisposed, isTrue);
    expect(stop.debugDisposed, isFalse);
    expect(price.debugDisposed, isFalse);
    cache.clear();
    expect(cache.length, 0);
    expect(cache.pillLength, 0);
    expect(stop.debugDisposed, isTrue);
    expect(price.debugDisposed, isTrue);
    expect(() => cache.layoutPill('X', maxWidth: 0), throwsArgumentError);
    expect(() => ChartTextLayoutCache(pillCapacity: 0), throwsArgumentError);
  });

  test('rectangle time text keeps normal weight separate from chart price',
      () {
    final cache = ChartTextLayoutCache();
    addTearDown(cache.clear);
    final normal = cache.layout('14/11 22:25 UTC', Colors.white, 11.5,
        fontWeight: FontWeight.normal);
    final same = cache.layout('14/11 22:25 UTC', Colors.white, 11.5,
        fontWeight: FontWeight.normal);
    final medium = cache.layout('14/11 22:25 UTC', Colors.white, 11.5);
    expect(identical(normal, same), isTrue);
    expect(identical(normal, medium), isFalse);
    expect(cache.length, 2);
    expect((normal.text! as TextSpan).style!.fontWeight, FontWeight.normal);
    expect((medium.text! as TextSpan).style!.fontWeight, FontWeight.w500);
    expect(normal.textDirection, TextDirection.ltr);
    expect(normal.maxLines, 1);
  });
}
