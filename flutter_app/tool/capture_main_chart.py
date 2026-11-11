"""Verify and capture the real Android chart shell for PROMPT 08.

The screenshot intentionally preserves an unauthenticated cTrader empty
state. It never inserts screenshot OHLC or a synthetic chart into the app.
"""

from pathlib import Path
import subprocess
import sys
import time

from capture_drawing_tools_sheet import center_of, ui_tree


def main():
    if len(sys.argv) != 2:
        print("Usage: capture_main_chart.py <output.png>", file=sys.stderr)
        return 2
    root = None
    for _ in range(6):
        root = ui_tree()
        if (center_of(root, "1 دق") and
                center_of(root, "GOLD") and
                center_of(root, "أدوات الرسم")):
            break
        time.sleep(3)
    else:
        print("TradeLab's real GOLD / 1-minute chart shell did not appear.")
        return 1
    destination = Path(sys.argv[1])
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as out:
        subprocess.run(["adb", "exec-out", "screencap", "-p"],
                       stdout=out, check=True, timeout=30)
    print("Captured actual TradeLab GOLD screen:", destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
