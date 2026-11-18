import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/replay/replay_mobile_controls.dart';
import 'package:tradelab_flutter/replay/replay_playback_speed.dart';

void main() {
  for (final width in <double>[320, 390]) {
    testWidgets('Replay selection confirm remains hittable at ${width}dp',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var confirmations = 0;
      ReplayStartMenuAction? chosen;
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: Column(children: [
          const Spacer(),
          ReplayMobileControls(
            selecting: true, playing: false,
            visibleCount: 1, totalBars: 100,
            chartFrame: '3m',
            speed: ReplayPlaybackSpeed.normal,
            showTrading: false, showDrawingTools: false,
            canLoadOlder: true, olderLoading: false, tradeCount: 0,
            autoStep: true,
            onClose: () {},
            onConfirm: () => confirmations++,
            onStartMenu: (action) => chosen = action,
            onExtras: (_) {},
            onStepMenu: (_) {},
            onReset: () {},
            onStepBack: () {},
            onStepForward: () {},
            onPlayPause: () {},
            onSpeed: (_) {},
            onChooseAgain: () {},
          ),
        ]),
      )));
      final confirm = find.byKey(const Key('replay-confirm-start'));
      expect(confirm, findsOneWidget);
      final center = tester.getCenter(confirm);
      expect(center.dx, greaterThan(0));
      expect(center.dx, lessThan(width));
      await tester.tap(confirm);
      await tester.pump();
      expect(confirmations, 1);

      await tester.tap(find.byKey(const Key('replay-start-menu')));
      await tester.pumpAndSettle();
      expect(find.text('حدد تاريخًا...'), findsOneWidget);
      await tester.tap(find.byKey(const Key('replay-pick-random')));
      await tester.pumpAndSettle();
      expect(chosen, ReplayStartMenuAction.random);
      await tester.tap(find.byKey(const Key('replay-more-actions')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('replay-practice-order')), findsOneWidget);
      expect(tester.widget<PopupMenuItem<ReplayExtrasAction>>(
        find.byKey(const Key('replay-practice-order'))).enabled, isFalse,
        reason: 'Cannot open training until the start candle is confirmed');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Play and new start stay visible in active Replay at ${width}dp',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var played = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: Column(children: [
          const Spacer(),
          ReplayMobileControls(
            selecting: false, playing: false,
            visibleCount: 15, totalBars: 100,
            chartFrame: '3m',
            speed: ReplayPlaybackSpeed.normal,
            showTrading: false, showDrawingTools: false,
            canLoadOlder: true, olderLoading: false, tradeCount: 0,
            autoStep: true,
            onClose: () {},
            onConfirm: () {},
            onStartMenu: (_) {},
            onExtras: (_) {},
            onStepMenu: (_) {},
            onReset: () {},
            onStepBack: () {},
            onStepForward: () {},
            onPlayPause: () => played++,
            onSpeed: (_) {},
            onChooseAgain: () {},
          ),
        ]),
      )));
      final play = find.byKey(const Key('replay-play-pause'));
      final again = find.byKey(const Key('replay-choose-new-start'));
      expect(play, findsOneWidget);
      expect(again, findsOneWidget);
      expect(tester.getCenter(play).dx, lessThan(width));
      expect(tester.getCenter(again).dx, lessThan(width));
      await tester.tap(play);
      await tester.pump();
      expect(played, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Replay displays native 2m and 2h intervals in Arabic',
      (tester) async {
    Widget controls(String frame) => MaterialApp(home: Scaffold(
      body: Column(children: [
        const Spacer(),
        ReplayMobileControls(
          selecting: false, playing: false,
          visibleCount: 3, totalBars: 100,
          chartFrame: frame,
          speed: ReplayPlaybackSpeed.normal,
          showTrading: false, showDrawingTools: false,
          canLoadOlder: false, olderLoading: false, tradeCount: 0,
          autoStep: true,
          onClose: () {}, onConfirm: () {}, onStartMenu: (_) {},
          onExtras: (_) {}, onStepMenu: (_) {}, onReset: () {},
          onStepBack: () {}, onStepForward: () {}, onPlayPause: () {},
          onSpeed: (_) {}, onChooseAgain: () {},
        ),
      ]),
    ));
    await tester.pumpWidget(controls('2m'));
    expect(find.text('2 دق'), findsOneWidget);
    await tester.pumpWidget(controls('2h'));
    expect(find.text('ساعتان'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in <double>[320, 390]) {
    testWidgets('Replay step transport stays tappable after scrolling settings at ${width}dp',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var exits = 0;
      var stepsBack = 0;
      var stepsForward = 0;
      var playback = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: Column(children: [
          const Spacer(),
          ReplayMobileControls(
            selecting: false, playing: false,
            visibleCount: 15, totalBars: 100,
            chartFrame: '1h',
            speed: ReplayPlaybackSpeed.normal,
            showTrading: false, showDrawingTools: false,
            canLoadOlder: true, olderLoading: false, tradeCount: 0,
            autoStep: true,
            onClose: () => exits++,
            onConfirm: () {},
            onStartMenu: (_) {}, onExtras: (_) {},
            onStepMenu: (_) {}, onReset: () {},
            onStepBack: () => stepsBack++,
            onStepForward: () => stepsForward++,
            onPlayPause: () => playback++,
            onSpeed: (_) {}, onChooseAgain: () {},
          ),
        ]),
      )));
      final back = find.byKey(const Key('replay-step-back'));
      final play = find.byKey(const Key('replay-play-pause'));
      final next = find.byKey(const Key('replay-step-forward'));
      final close = find.byKey(const Key('replay-close'));
      final more = find.byKey(const Key('replay-more-actions'));
      for (final control in [close, back, play, next, more]) {
        expect(control, findsOneWidget);
        final center = tester.getCenter(control);
        expect(center.dx, greaterThanOrEqualTo(0));
        expect(center.dx, lessThanOrEqualTo(width));
        expect(tester.getRect(control).width, greaterThanOrEqualTo(38));
      }
      final before = [back, play, next].map(
          (control) => tester.getCenter(control).dx).toList();
      await tester.drag(find.byType(SingleChildScrollView).first,
          const Offset(-240, 0));
      await tester.pumpAndSettle();
      final after = [back, play, next].map(
          (control) => tester.getCenter(control).dx).toList();
      expect(after, before,
          reason: 'Main Replay transport must never scroll offscreen');
      await tester.tap(back);
      await tester.tap(play);
      await tester.tap(next);
      await tester.tap(close);
      await tester.pump();
      expect(stepsBack, 1);
      expect(playback, 1);
      expect(stepsForward, 1);
      expect(exits, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Replay start confirm stays pinned while options scroll at ${width}dp',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var confirmed = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: Column(children: [
          const Spacer(),
          ReplayMobileControls(
            selecting: true, playing: false,
            visibleCount: 1, totalBars: 100,
            chartFrame: '1m',
            speed: ReplayPlaybackSpeed.normal,
            showTrading: false, showDrawingTools: false,
            canLoadOlder: false, olderLoading: false, tradeCount: 0,
            autoStep: true,
            onClose: () {},
            onConfirm: () => confirmed++,
            onStartMenu: (_) {}, onExtras: (_) {},
            onStepMenu: (_) {}, onReset: () {},
            onStepBack: () {},
            onStepForward: () {},
            onPlayPause: () {},
            onSpeed: (_) {}, onChooseAgain: () {},
          ),
        ]),
      )));
      expect(find.byKey(const Key('replay-step-back')), findsNothing);
      expect(find.byKey(const Key('replay-step-forward')), findsNothing);
      expect(find.byKey(const Key('replay-play-pause')), findsNothing);
      expect(find.byKey(const Key('replay-choose-new-start')), findsNothing);
      final confirm = find.byKey(const Key('replay-confirm-start'));
      final position = tester.getCenter(confirm);
      await tester.drag(find.byType(SingleChildScrollView).first,
          const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(tester.getCenter(confirm), position);
      await tester.tap(confirm);
      await tester.pump();
      expect(confirmed, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
