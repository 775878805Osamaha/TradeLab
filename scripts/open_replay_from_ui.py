#!/usr/bin/env python3
"""Tap the embedded Replay button using actual Android accessibility bounds."""
import re
import subprocess
import xml.etree.ElementTree as ET

root = ET.parse("screenshots/tradelab-before-replay.xml").getroot()
candidates = []
for node in root.iter("node"):
    label = (node.attrib.get("text", "") + " " + node.attrib.get("content-desc", "")).strip()
    if label == "Replay" or "إعادة العرض داخل الشارت" in label:
        match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.attrib.get("bounds", ""))
        if match:
            x1, y1, x2, y2 = map(int, match.groups())
            candidates.append((label, (x1 + x2) // 2, (y1 + y2) // 2))
if not candidates:
    raise SystemExit("Replay control not found in real accessibility tree")
label, x, y = candidates[0]
print("Opening embedded Replay:", label, x, y, flush=True)
subprocess.run(["adb", "shell", "input", "tap", str(x), str(y)], check=True)
