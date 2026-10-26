#!/usr/bin/env python3
"""Extract measured frame timing from retained UTP per-test logcat, after APK cleanup."""
from pathlib import Path
import json
import re

root = Path('app/build/outputs/androidTest-results/connected')
for path in root.rglob('*recordActualPanFrameDurations*.txt'):
    for line in path.read_text(errors='replace').splitlines():
        if 'TradeLabFrameMetrics' not in line:
            continue
        match = re.search(r'(\{"samples".*\})', line)
        if match:
            measured = json.loads(match.group(1))
            Path('screenshots/chart-frame-metrics.json').write_text(json.dumps(measured, indent=2))
            print(json.dumps(measured, indent=2))
            raise SystemExit(0)
raise SystemExit('Frame metric entry missing from retained per-test logcat')
