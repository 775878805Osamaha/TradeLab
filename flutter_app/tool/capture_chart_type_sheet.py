"""Capture TradeLab's chart-kind sheet from an actual Android emulator.

The emulator action runs each configured script line in a separate shell, so
stateful XML parsing and tapping belong in a single executable command.
"""

from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: capture_chart_type_sheet.py <screenshot.png>", file=sys.stderr)
        return 2

    result = subprocess.run(
        ["adb", "exec-out", "uiautomator", "dump", "/dev/tty"],
        capture_output=True,
        text=True,
        check=False,
        timeout=35,
    )
    raw = result.stdout
    start = raw.find("<?xml")
    if start < 0:
        start = raw.find("<hierarchy")
    if start < 0:
        print("No Android UI XML available; skipped screenshot.")
        return 0

    try:
        root = ET.fromstring(raw[start:])
    except ET.ParseError:
        print("Android UI XML could not be parsed; skipped screenshot.")
        return 0

    for node in root.iter("node"):
        label = (node.get("content-desc") or "") + " " + (node.get("text") or "")
        if "نوع الشموع" not in label:
            continue
        numbers = re.findall(r"\d+", node.get("bounds") or "")
        if len(numbers) != 4:
            continue
        x1, y1, x2, y2 = map(int, numbers)
        x, y = (x1 + x2) // 2, (y1 + y2) // 2
        subprocess.run(["adb", "shell", "input", "tap", str(x), str(y)],
                       check=True, timeout=20)
        time.sleep(3)
        destination = Path(sys.argv[1])
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("wb") as output:
            subprocess.run(["adb", "exec-out", "screencap", "-p"],
                           stdout=output, check=True, timeout=20)
        print("Captured open chart-kind sheet at:", destination)
        return 0

    print("Chart-kind toolbar semantics not found; skipped screenshot.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
