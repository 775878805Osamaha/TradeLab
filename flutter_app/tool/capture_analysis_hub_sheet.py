"""Capture PROMPT 06 analysis commands as an actual Android screenshot.

The previous step leaves the trend tool catalog open. Close it, open the
analysis hub from the real chart toolbar and verify reference labels in the
Android accessibility tree before capturing. No mock chart is rendered.
"""

from pathlib import Path
import subprocess
import sys
import time

from capture_drawing_tools_sheet import center_of, ui_tree


def main():
    if len(sys.argv) != 2:
        print("Usage: capture_analysis_hub_sheet.py <output.png>",
              file=sys.stderr)
        return 2

    subprocess.run(["adb", "shell", "input", "keyevent", "4"],
                   check=True, timeout=20)
    time.sleep(1)
    target = None
    for _ in range(5):
        target = center_of(ui_tree(), "محور التحليل")
        if target:
            break
        time.sleep(2)
    if not target:
        print("The actual chart analysis-hub command was not accessible.")
        return 1

    subprocess.run(["adb", "shell", "input", "tap",
                    str(target[0]), str(target[1])], check=True, timeout=20)
    time.sleep(3)
    root = ui_tree()
    for label in ("محور التحليل", "تداول مع وسيطك", "إعادة تشغيل الأعمدة"):
        if not center_of(root, label):
            print("Missing reference section in the real Android sheet:", label)
            return 1

    destination = Path(sys.argv[1])
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as out:
        subprocess.run(["adb", "exec-out", "screencap", "-p"],
                       stdout=out, check=True, timeout=20)
    print("Captured real TradeLab analysis hub:", destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
