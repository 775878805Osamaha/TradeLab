#!/usr/bin/env python3
"""Keep actual UI captures available even when an instrumentation assertion fails."""
import subprocess
import sys
result = subprocess.run(['./gradlew', 'connectedDebugAndroidTest', '--stacktrace'])
collector = subprocess.run([sys.executable, 'scripts/collect_provider_screenshots.py', '--allow-missing' if result.returncode else '--strict'])
sys.exit(result.returncode or collector.returncode)
