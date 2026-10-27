#!/usr/bin/env python3
"""Collect actual source checks after the instrumentation runner cleans up its APK."""
import datetime
import subprocess
import sys

names = ['tradelab-replay-account', 'tradelab-replay-results', 'tradelab-market-terminal', 'tradelab-gold-3m', 'tradelab-position-actions', 'tradelab-compact-replay'] + ['drawing-catalog-' + name for name in ['favorites', 'shapes', 'notes', 'patterns', 'measurement', 'triangle']]
if datetime.datetime.now(datetime.timezone.utc).weekday() < 5:
    names.append('tradelab-gold-trade')
for name in names:
    result = subprocess.run(['adb', 'pull', f'/sdcard/Download/{name}.png', f'screenshots/{name}.png'])
    if result.returncode and "--allow-missing" not in sys.argv:
        raise SystemExit(result.returncode)
