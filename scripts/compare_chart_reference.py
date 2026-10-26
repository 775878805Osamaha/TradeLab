#!/usr/bin/env python3
"""Compare real captures with the supplied target. Never treats OHLC differences as UI failures."""
from pathlib import Path
from PIL import Image, ImageChops, ImageEnhance
import json
import xml.etree.ElementTree as ET

reference = Image.open('docs/chart-reference/reference.png').convert('RGB')
actual = Image.open('screenshots/tradelab-150s.png').convert('RGB')
resized = actual.resize(reference.size, Image.Resampling.LANCZOS)
Image.blend(reference, resized, .5).save('screenshots/reference-overlay.png')
ImageEnhance.Contrast(ImageChops.difference(reference, resized)).enhance(3).save('screenshots/reference-difference.png')
# These image regions contain market-dependent candles, prices and system chrome.
# Publish raw evidence; do not make a misleading global pixel-perfect assertion.
regions = {'plot': (110, 153, 745, 1214), 'price_axis': (745, 153, 864, 1214),
           'drawing_rail': (14, 164, 110, 1190), 'time_axis': (0, 1214, 864, 1264),
           'bottom_strip': (0, 1264, 864, 1361), 'navigation': (14, 1374, 849, 1500)}
root = ET.parse('screenshots/tradelab-ui.xml').getroot()
nodes = list(root.iter('node'))
controls = {}
for label in ['XAUUSD', 'GOLD', 'الفاصل الزمني', 'إعادة العرض داخل الشارت', 'السوق', 'الشارت', 'النتائج', 'الحساب']:
    matches = [n.attrib for n in nodes if label in (n.attrib.get('text', ''), n.attrib.get('content-desc', ''))]
    controls[label] = [{'bounds': n.get('bounds'), 'selected': n.get('selected')} for n in matches]
report = {'reference_size': reference.size, 'actual_size': actual.size,
          'reference_regions_px': regions, 'actual_accessibility_controls': controls,
          'visual_result': 'REQUIRES_MANUAL_REVIEW',
          'limits': ['OHLC, price labels, timestamps, battery and system bars vary.',
                     'Overlay is a review artifact, not evidence of pixel-perfect fidelity.',
                     'No FPS assertion: this job does not measure frame timing.']}
Path('screenshots/reference-comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps(report, ensure_ascii=False, indent=2))
