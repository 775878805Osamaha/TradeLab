"""Capture the real PROMPT 09 favorite groups over the unchanged chart.

The previous workflow screenshot has the general drawing commands open.
Accessibility data identifies category targets; gestures only scroll the
category strip to make its rightmost item reachable.
"""

from pathlib import Path
import re
import subprocess
import sys
import time

from capture_drawing_tools_sheet import center_of, ui_tree


def exact_bounds(root, label):
    if root is None:
        return None
    for node in root.iter('node'):
        if label not in (node.get('text'), node.get('content-desc')):
            continue
        values = re.findall(r'\d+', node.get('bounds') or '')
        if len(values) == 4:
            return tuple(map(int, values))
    return None


def adb(*args):
    subprocess.run(['adb', *args], check=True, timeout=25)


def main():
    if len(sys.argv) != 2:
        print('Usage: capture_favorite_drawing_tools_sheet.py <output.png>',
              file=sys.stderr)
        return 2

    adb('shell', 'input', 'keyevent', '4')
    time.sleep(1)
    trigger = None
    for _ in range(5):
        trigger = center_of(ui_tree(), 'أدوات الرسم')
        if trigger:
            break
        time.sleep(2)
    if not trigger:
        print('Cannot find actual chart drawing catalog control')
        return 1
    adb('shell', 'input', 'tap', str(trigger[0]), str(trigger[1]))
    time.sleep(2)

    width = int(subprocess.check_output(['adb', 'shell', 'wm', 'size'],
                                        text=True).strip().split(':')[-1]
                .strip().split('x')[0])
    chosen = False
    for _ in range(6):
        root = ui_tree()
        rect = exact_bounds(root, 'المفضلة')
        if rect:
            x1, y1, x2, y2 = rect
            target_x = (x1 + x2) // 2
            target_y = (y1 + y2) // 2
            if 15 < target_x < width - 15:
                adb('shell', 'input', 'tap', str(target_x), str(target_y))
                chosen = True
                break
        anchor = exact_bounds(root, 'أدوات الاتجاه')
        if not anchor:
            break
        category_y = (anchor[1] + anchor[3]) // 2
        adb('shell', 'input', 'swipe', str(int(width * .83)),
            str(category_y), str(int(width * .28)), str(category_y), '250')
        time.sleep(.5)

    if not chosen:
        print('Could not select favorites on actual Android category strip')
        return 1
    time.sleep(2)
    root = ui_tree()
    for label in ('أدوات الاتجاه', 'جان وفيبوناتشي',
                  'إظهار المفضلة على الرسم البياني'):
        if not center_of(root, label):
            print('Missing section/footer from real Android sheet:', label)
            return 1

    # Restore the strip's original clipping. The selection itself is retained.
    rect = exact_bounds(root, 'أدوات الاتجاه')
    if rect:
        y = (rect[1] + rect[3]) // 2
        adb('shell', 'input', 'swipe', str(int(width * .2)),
            str(y), str(int(width * .85)), str(y), '230')
        time.sleep(.5)

    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('wb') as stream:
        subprocess.run(['adb', 'exec-out', 'screencap', '-p'],
                       stdout=stream, check=True, timeout=25)
    print('Captured real PROMPT 09 favorites screenshot:', output)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
