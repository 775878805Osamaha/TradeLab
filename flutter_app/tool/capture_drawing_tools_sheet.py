"""Capture the real TradeLab Gann/Fibonacci drawing catalog on Android 13.

The UI is driven by accessibility labels, not hardcoded tap coordinates.
The chart-kind screenshot step may have left another modal open, so dismiss
that first. A screenshot is published only when the drawing sheet is visible.
"""

from pathlib import Path
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET


def ui_tree():
    out = subprocess.run(
        ["adb", "exec-out", "uiautomator", "dump", "/dev/tty"],
        capture_output=True, text=True, check=False, timeout=35,
    ).stdout
    start = out.find("<?xml")
    if start < 0:
        start = out.find("<hierarchy")
    end = out.rfind("</hierarchy>")
    if start < 0 or end < 0:
        return None
    try:
        return ET.fromstring(out[start:end + len("</hierarchy>")])
    except ET.ParseError:
        return None


def center_of(root, target):
    if root is None:
        return None
    for node in root.iter("node"):
        text = (node.get("content-desc") or "") + " " + (node.get("text") or "")
        if target not in text:
            continue
        values = re.findall(r"\d+", node.get("bounds") or "")
        if len(values) == 4:
            a, b, c, d = map(int, values)
            return ((a+c)//2, (b+d)//2)
    return None


def main():
    if len(sys.argv) != 2:
        print("Usage: capture_drawing_tools_sheet.py <screenshot.png>",
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
        print("Drawing tools entry was not found in the actual Android UI.")
        return 1
    subprocess.run(["adb", "shell", "input", "tap",
                    str(target[0]), str(target[1])], check=True, timeout=20)
    time.sleep(3)
    root = ui_tree()
    if not center_of(root, "جان وفيبوناتشي"):
        print("Gann/Fibonacci category not visible after opening drawings.")
        return 1
    destination = Path(sys.argv[1])
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as output:
        subprocess.run(["adb", "exec-out", "screencap", "-p"],
                       stdout=output, check=True, timeout=20)
    print("Captured real Gann/Fibonacci drawing sheet:", destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
