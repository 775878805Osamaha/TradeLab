"""Capture the PROMPT 05 trend drawing sheet from an Android 13 emulator.

The previous CI step leaves the Gann/Fibonacci catalog open. Close it, open
the actual chart drawing entry again, and verify the selected trend tab.
Tap targets are always derived from the Android accessibility tree.
"""

from pathlib import Path
import subprocess
import sys
import time

from capture_drawing_tools_sheet import center_of, ui_tree


def main():
    if len(sys.argv) != 2:
        print("Usage: capture_trend_drawing_tools_sheet.py <screenshot.png>",
              file=sys.stderr)
        return 2

    subprocess.run(["adb", "shell", "input", "keyevent", "4"],
                   check=True, timeout=20)
    time.sleep(1)

    target = None
    for _ in range(4):
        target = center_of(ui_tree(), "أدوات الرسم")
        if target:
            break
        time.sleep(2)
    if not target:
        print("Chart drawing tools trigger not present in Android UI")
        return 1

    subprocess.run(["adb", "shell", "input", "tap",
                    str(target[0]), str(target[1])], check=True, timeout=20)
    time.sleep(3)
    root = ui_tree()
    if not center_of(root, "أدوات الاتجاه"):
        print("Trend category missing from live Android sheet")
        return 1
    if not center_of(root, "قناة متوازية"):
        print("Parallel channel tile missing from live Android sheet")
        return 1

    destination = Path(sys.argv[1])
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as output:
        subprocess.run(["adb", "exec-out", "screencap", "-p"],
                       stdout=output, check=True, timeout=20)
    print("Captured real TradeLab trend drawing catalog:", destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
