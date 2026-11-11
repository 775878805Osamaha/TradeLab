"""Capture PROMPT 11 panel, PROMPT 13 scales and PROMPT 14 symbol editor.

The prior workflow step leaves favorites open. Navigate using the Android
accessibility tree; capture both the available upper reference and the lower
buttons/margins area. No synthetic candles or broker prices are involved.
"""

from pathlib import Path
import subprocess
import sys
import time

from capture_drawing_tools_sheet import center_of, ui_tree


def adb(*args):
    subprocess.run(['adb', *args], check=True, timeout=30)


def tap_label(label, tries=6):
    for _ in range(tries):
        center = center_of(ui_tree(), label)
        if center:
            adb('shell', 'input', 'tap', str(center[0]), str(center[1]))
            time.sleep(1.5)
            return True
        time.sleep(1)
    return False


def save(path):
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open('wb') as target:
        subprocess.run(['adb', 'exec-out', 'screencap', '-p'],
                       stdout=target, check=True, timeout=25)
    print('Captured:', destination)


def main():
    if len(sys.argv) not in (3, 4, 5):
        print('Usage: capture_panel_settings.py <top.png> <bottom.png> '
              '[price-scale.png] [symbol.png]',
              file=sys.stderr)
        return 2

    adb('shell', 'input', 'keyevent', '4')
    time.sleep(1)
    if not tap_label('محور التحليل'):
        print('Could not find chart analysis command', file=sys.stderr)
        return 1
    if not tap_label('إعداد التنسيق'):
        print('Could not find layout format', file=sys.stderr)
        return 1
    root = ui_tree()
    if not center_of(root, 'لوحة') or not center_of(root, 'موافق'):
        print('Actual panel page or footer is absent', file=sys.stderr)
        return 1
    save(sys.argv[1])

    screen = subprocess.check_output(['adb', 'shell', 'wm', 'size'],
                                     text=True).strip().split(':')[-1]
    width, height = map(int, screen.strip().split('x'))
    header_y = center_of(root, 'لوحة')[1]
    footer_y = center_of(root, 'موافق')[1]
    for _ in range(5):
        if center_of(ui_tree(), 'هوامش'):
            break
        adb('shell', 'input', 'swipe', str(width // 2),
            str(max(header_y + 160, footer_y - 155)), str(width // 2),
            str(header_y + 95), '400')
        time.sleep(1)
    else:
        print('Could not reach bottom margins through real scrolling',
              file=sys.stderr)
        return 1
    if not center_of(ui_tree(), 'موافق'):
        print('Fixed confirmation footer disappeared', file=sys.stderr)
        return 1
    save(sys.argv[2])
    if len(sys.argv) >= 4:
        if not tap_label('•••'):
            print('Could not open fixed settings more button', file=sys.stderr)
            return 1
        if not tap_label('المقاييس والخطوط'):
            print('Could not open price/time scale page', file=sys.stderr)
            return 1
        if not center_of(ui_tree(), 'إغلاق اليوم السابق'):
            # The price-scale page opens at top, matching the reference upper
            # frame. Scroll the actual form, never reposition screenshot pixels.
            for _ in range(5):
                adb('shell', 'input', 'swipe', str(width // 2),
                    str(max(header_y + 180, footer_y - 120)),
                    str(width // 2), str(header_y + 85), '400')
                time.sleep(.6)
                if center_of(ui_tree(), 'مقياس الوقت'):
                    break
        for _ in range(5):
            if center_of(ui_tree(), 'مقياس الوقت'):
                break
            adb('shell', 'input', 'swipe', str(width // 2),
                str(max(header_y + 180, footer_y - 120)),
                str(width // 2), str(header_y + 85), '400')
            time.sleep(.6)
        else:
            print('Could not reach the time-scale section', file=sys.stderr)
            return 1
        if not center_of(ui_tree(), 'موافق'):
            print('Scale page confirmation footer disappeared', file=sys.stderr)
            return 1
        save(sys.argv[3])
    if len(sys.argv) == 5:
        adb('shell', 'input', 'keyevent', '4')
        time.sleep(1.4)
        if not tap_label('•••'):
            print('Could not open symbol navigation', file=sys.stderr)
            return 1
        if not tap_label('رمز'):
            print('Could not open symbol editor', file=sys.stderr)
            return 1
        root = ui_tree()
        if not center_of(root, 'تلوين الأعمدة طبقًا للإغلاق السابق'):
            print('Symbol settings controls not found', file=sys.stderr)
            return 1
        if not center_of(root, 'موافق'):
            print('Symbol editor fixed footer absent', file=sys.stderr)
            return 1
        save(sys.argv[4])
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
