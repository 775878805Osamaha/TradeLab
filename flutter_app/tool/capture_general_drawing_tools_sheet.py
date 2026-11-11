"""Capture actual PROMPT 07 general chart commands on an Android emulator.

The analysis-hub sheet from the preceding capture is closed first. Locate
the drawing tools button and selected category from accessibility data;
never substitute a synthetic Flutter screenshot for emulator evidence.
"""

from pathlib import Path
import re
import subprocess
import sys
import time

from capture_drawing_tools_sheet import center_of, ui_tree


def exact_label_center(root, label):
    if root is None:
        return None
    for node in root.iter("node"):
        if label not in (node.get("text"), node.get("content-desc")):
            continue
        values = re.findall(r"\d+", node.get("bounds") or "")
        if len(values) == 4:
            left, top, right, bottom = map(int, values)
            return ((left + right) // 2, (top + bottom) // 2)
    return None


def main():
    if len(sys.argv) != 2:
        print("Usage: capture_general_drawing_tools_sheet.py <output.png>",
              file=sys.stderr)
        return 2

    subprocess.run(["adb", "shell", "input", "keyevent", "4"],
                   check=True, timeout=20)
    time.sleep(1)
    trigger = None
    for _ in range(5):
        trigger = center_of(ui_tree(), "أدوات الرسم")
        if trigger:
            break
        time.sleep(2)
    if not trigger:
        print("Unable to locate chart drawing tools on the real device")
        return 1
    subprocess.run(["adb", "shell", "input", "tap",
                    str(trigger[0]), str(trigger[1])], check=True, timeout=20)
    time.sleep(2)
    category = exact_label_center(ui_tree(), "أدوات")
    if not category:
        print("General tools category is not available on Android")
        return 1
    subprocess.run(["adb", "shell", "input", "tap",
                    str(category[0]), str(category[1])], check=True, timeout=20)
    time.sleep(2)
    root = ui_tree()
    for label in ("مقياس", "ممحاة", "تكبير", "تصغير"):
        if not center_of(root, label):
            print("Real Android sheet is missing command:", label)
            return 1

    destination = Path(sys.argv[1])
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as out:
        subprocess.run(["adb", "exec-out", "screencap", "-p"],
                       stdout=out, check=True, timeout=20)
    print("Captured real TradeLab general drawing commands:", destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
