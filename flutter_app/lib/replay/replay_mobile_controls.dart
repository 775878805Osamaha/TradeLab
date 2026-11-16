import 'package:flutter/material.dart';
import 'replay_playback_speed.dart';

enum ReplayStartMenuAction {
  column, date, earliest, random, toggleTrading,
}
enum ReplayStepMenuAction { currentBar, auto, information }

/// Compact controls on the SAME chart, never a new page or fake price engine.
/// All actions delegate to ChartScreen and its source-verified Replay state.
class ReplayMobileControls extends StatelessWidget {
  const ReplayMobileControls({
    required this.selecting,
    required this.playing,
    required this.visibleCount,
    required this.totalBars,
    required this.chartFrame,
    required this.speed,
    required this.showTrading,
    required this.autoStep,
    required this.onClose,
    required this.onConfirm,
    required this.onStartMenu,
    required this.onStepMenu,
    required this.onReset,
    required this.onStepBack,
    required this.onStepForward,
    required this.onPlayPause,
    required this.onSpeed,
    required this.onChooseAgain,
    super.key,
  });

  final bool selecting;
  final bool playing;
  final int visibleCount;
  final int totalBars;
  final String chartFrame;
  final ReplayPlaybackSpeed speed;
  final bool showTrading;
  final bool autoStep;
  final VoidCallback onClose;
  final VoidCallback onConfirm;
  final ValueChanged<ReplayStartMenuAction> onStartMenu;
  final ValueChanged<ReplayStepMenuAction> onStepMenu;
  final VoidCallback onReset;
  final VoidCallback onStepBack;
  final VoidCallback onStepForward;
  final VoidCallback onPlayPause;
  final ValueChanged<ReplayPlaybackSpeed> onSpeed;
  final VoidCallback onChooseAgain;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF181818);
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      key: const Key('replay-controls'),
      height: 58,
      color: surface,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Directionality(
        textDirection: TextDirection.ltr,
        // Play/Confirm and pick-new-start are pinned on the phone. Only the
        // secondary controls may scroll horizontally on 320dp screens.
        child: Row(children: [
          Expanded(child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              key: const Key('replay-close'),
              tooltip: 'إغلاق Replay',
              onPressed: onClose,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              icon: const Icon(Icons.close, size: 25, color: ink),
            ),
            PopupMenuButton<ReplayStartMenuAction>(
              key: const Key('replay-start-menu'),
              tooltip: 'اختيار نقطة بداية Replay',
              position: PopupMenuPosition.over,
              constraints: const BoxConstraints(minWidth: 250, maxWidth: 320),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              onSelected: onStartMenu,
              icon: const Icon(Icons.settings_outlined, color: ink),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  key: Key('replay-pick-column'),
                  value: ReplayStartMenuAction.column,
                  child: Row(children: [
                    Icon(Icons.first_page, color: ink),
                    SizedBox(width: 16),
                    Expanded(child: Text('حدد العمود',
                      textDirection: TextDirection.rtl)),
                  ])),
                const PopupMenuItem(
                  key: Key('replay-pick-date'),
                  value: ReplayStartMenuAction.date,
                  child: Row(children: [
                    Icon(Icons.event, color: ink),
                    SizedBox(width: 16),
                    Expanded(child: Text('حدد تاريخًا...',
                      textDirection: TextDirection.rtl)),
                  ])),
                const PopupMenuItem(
                  key: Key('replay-pick-earliest'),
                  value: ReplayStartMenuAction.earliest,
                  child: Row(children: [
                    Icon(Icons.flag_outlined, color: ink),
                    SizedBox(width: 16),
                    Expanded(child: Text('حدد أول تاريخ متاح',
                      textDirection: TextDirection.rtl)),
                  ])),
                const PopupMenuItem(
                  key: Key('replay-pick-random'),
                  value: ReplayStartMenuAction.random,
                  child: Row(children: [
                    Icon(Icons.casino_outlined, color: ink),
                    SizedBox(width: 16),
                    Expanded(child: Text('عمود عشوائي',
                      textDirection: TextDirection.rtl)),
                  ])),
                CheckedPopupMenuItem(
                  key: const Key('replay-show-trading-menu'),
                  value: ReplayStartMenuAction.toggleTrading,
                  checked: showTrading,
                  child: const Text('إظهار أزرار التداول',
                    textDirection: TextDirection.rtl)),
              ],
            ),
            IconButton(
              key: const Key('replay-reset-start'),
              tooltip: 'الرجوع إلى بداية Replay',
              onPressed: selecting ? null : onReset,
              constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.first_page_outlined, color: ink),
            ),
            PopupMenuButton<ReplayStepMenuAction>(
              key: const Key('replay-interval-picker'),
              tooltip: 'تحديد فاصل تقدم Replay',
              position: PopupMenuPosition.over,
              constraints: const BoxConstraints(minWidth: 255, maxWidth: 315),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              onSelected: onStepMenu,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                child: Text(_frameLabel(chartFrame),
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontSize: 16,
                      color: ink, fontWeight: FontWeight.w700)),
              ),
              itemBuilder: (_) => [
                const PopupMenuItem<ReplayStepMenuAction>(
                  enabled: false,
                  child: Text('1 تيك · غير متاح دون تاريخ Tick',
                    textDirection: TextDirection.rtl)),
                const PopupMenuItem<ReplayStepMenuAction>(
                  enabled: false,
                  child: Text('1 ثانية · غير متاح دون بيانات ثانية',
                    textDirection: TextDirection.rtl)),
                if (chartFrame != '1m')
                  const PopupMenuItem<ReplayStepMenuAction>(
                    enabled: false,
                    child: Text('1 دقيقة · لا تتوفر بيانات أدق لهذه الشموع',
                      textDirection: TextDirection.rtl)),
                CheckedPopupMenuItem(
                  key: const Key('replay-current-interval'),
                  value: ReplayStepMenuAction.currentBar,
                  checked: true,
                  child: Text('شمعة كاملة · ${_frameLabel(chartFrame)}',
                    textDirection: TextDirection.rtl)),
                CheckedPopupMenuItem(
                  key: const Key('replay-auto-interval'),
                  value: ReplayStepMenuAction.auto,
                  checked: autoStep,
                  child: const Text('تحديد الفاصل الزمني تلقائيًا',
                    textDirection: TextDirection.rtl)),
                const PopupMenuItem(
                  key: Key('replay-interval-info'),
                  value: ReplayStepMenuAction.information,
                  child: Text('المزيد من المعلومات',
                    textDirection: TextDirection.rtl)),
              ],
            ),
            const SizedBox(width: 2),
            DropdownButton<ReplayPlaybackSpeed>(
              key: const Key('replay-speed-picker'),
              value: speed,
              underline: const SizedBox.shrink(),
              icon: const SizedBox.shrink(),
              style: const TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 17, color: ink),
              items: [
                for (final option in ReplayPlaybackSpeed.values)
                  DropdownMenuItem(value: option,
                      child: Text(option.label)),
              ],
              onChanged: (option) {
                if (option != null) onSpeed(option);
              },
            ),
            IconButton(
              key: const Key('replay-step-back'),
              tooltip: 'العودة شمعة واحدة',
              onPressed: selecting || visibleCount <= 1 ? null : onStepBack,
              icon: const Icon(Icons.skip_previous_outlined),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
              padding: EdgeInsets.zero),
            IconButton(
              key: const Key('replay-step-forward'),
              tooltip: 'التقدم شمعة واحدة',
              onPressed: selecting || visibleCount >= totalBars
                  ? null : onStepForward,
              icon: const Icon(Icons.skip_next_outlined),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 44),
              padding: EdgeInsets.zero),
            ]),
          )),
            if (selecting)
              TextButton.icon(
                key: const Key('replay-confirm-start'),
                onPressed: onConfirm,
                icon: const Icon(Icons.check_circle, color: Color(0xFF2962FF)),
                label: const Text('بدء', textDirection: TextDirection.rtl))
            else
              IconButton(
                key: const Key('replay-play-pause'),
                tooltip: playing ? 'إيقاف Replay' : 'تشغيل Replay',
                onPressed: onPlayPause,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow,
                    color: ink, size: 30),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
                padding: EdgeInsets.zero),
            IconButton(
              key: const Key('replay-choose-new-start'),
              tooltip: 'اختيار شمعة بداية جديدة',
              onPressed: onChooseAgain,
              icon: const Icon(Icons.first_page, color: ink),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 44),
              padding: EdgeInsets.zero),
        ]),
      ),
    );
  }

  static String _frameLabel(String frame) => switch (frame) {
    '1m' => '1 دق',
    '3m' => '3 دق',
    '5m' => '5 دق',
    '15m' => '15 دق',
    '30m' => '30 دق',
    '1h' => '1 ساعة',
    '4h' => '4 ساعات',
    _ => frame,
  };
}
