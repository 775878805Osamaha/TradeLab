#!/usr/bin/env python3
"""Collect actual source checks after the instrumentation runner cleans up its APK."""
import datetime
import subprocess

names = ['tradelab-gold-3m', 'tradelab-position-actions', 'tradelab-compact-replay'] + ['drawing-catalog-' + name for name in ['favorites', 'shapes', 'notes', 'patterns', 'measurement', 'triangle']]
if datetime.datetime.now(datetime.timezone.utc).weekday() < 5:
    names.append('tradelab-gold-trade')
for name in names:
    subprocess.run(['adb', 'pull', f'/sdcard/Download/{name}.png', f'screenshots/{name}.png'], check=True)
