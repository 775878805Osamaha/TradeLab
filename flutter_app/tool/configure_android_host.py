"""Configure the generated, isolated Flutter Android host for OAuth callbacks.

Run after `flutter create`, before building the APK. Keeps native TradeLab's
`tradelab://` callback completely untouched.
"""

from pathlib import Path
from xml.etree import ElementTree as ET

manifest_path = Path('android/app/src/main/AndroidManifest.xml')
ET.register_namespace('android', 'http://schemas.android.com/apk/res/android')
android = '{http://schemas.android.com/apk/res/android}'
tree = ET.parse(manifest_path)
root = tree.getroot()
if not any(item.attrib.get(android + 'name') == 'android.permission.INTERNET'
           for item in root.findall('uses-permission')):
    permission = ET.Element('uses-permission', {android + 'name': 'android.permission.INTERNET'})
    root.insert(0, permission)

application = root.find('application')
assert application is not None
activity = application.find('activity')
assert activity is not None

if not any(data.attrib.get(android + 'scheme') == 'tradelabflutter'
           for intent in activity.findall('intent-filter')
           for data in intent.findall('data')):
    intent = ET.SubElement(activity, 'intent-filter')
    ET.SubElement(intent, 'action', {android + 'name': 'android.intent.action.VIEW'})
    ET.SubElement(intent, 'category', {android + 'name': 'android.intent.category.DEFAULT'})
    ET.SubElement(intent, 'category', {android + 'name': 'android.intent.category.BROWSABLE'})
    ET.SubElement(intent, 'data', {
        android + 'scheme': 'tradelabflutter',
        android + 'host': 'oauth',
        android + 'path': '/ctrader',
    })
tree.write(manifest_path, encoding='utf-8', xml_declaration=True)
