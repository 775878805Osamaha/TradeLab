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
            showTrading: true, autoStep: true,
            onClose: () {},
            onConfirm: () => confirmations++,
            onStartMenu: (action) => chosen = action,
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
            showTrading: true, autoStep: true,
            onClose: () {},
            onConfirm: () {},
            onStartMenu: (_) {},
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
}
