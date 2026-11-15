"""Configure a generated Flutter Android host for stable release signing in CI.

Use per-repository GitHub secrets; never commit a keystore or its passwords.
"""
import base64
import os
from pathlib import Path

required = (
    "SHOREBIRD_ANDROID_KEYSTORE_BASE64",
    "SHOREBIRD_ANDROID_STORE_PASSWORD",
    "SHOREBIRD_ANDROID_KEY_ALIAS",
    "SHOREBIRD_ANDROID_KEY_PASSWORD",
    "RUNNER_TEMP",
)
missing = [name for name in required if not os.environ.get(name)]
if missing:
    raise SystemExit("Missing required signing secrets/environment: " + ", ".join(missing))

gradle = Path("android/app/build.gradle.kts")
if not gradle.exists():
    raise SystemExit("Expected generated Android Kotlin Gradle file not found")
content = gradle.read_text(encoding="utf-8")
if "signingConfig = signingConfigs.getByName(\"debug\")" not in content:
    raise SystemExit("Expected Flutter-generated debug signing configuration not found")
if "    buildTypes {" not in content:
    raise SystemExit("Cannot locate buildTypes block; signing config was not changed")

keystore = Path(os.environ["RUNNER_TEMP"]) / "shorebird-android-release.jks"
keystore.write_bytes(base64.b64decode(
    os.environ["SHOREBIRD_ANDROID_KEYSTORE_BASE64"], validate=True
))
props = Path("android/key.properties")
# Write keystore path under runner temp, outside repository, using secure permissions.
props.write_text(
    "storeFile=" + str(keystore) + "\n"
    + "storePassword=" + os.environ["SHOREBIRD_ANDROID_STORE_PASSWORD"] + "\n"
    + "keyAlias=" + os.environ["SHOREBIRD_ANDROID_KEY_ALIAS"] + "\n"
    + "keyPassword=" + os.environ["SHOREBIRD_ANDROID_KEY_PASSWORD"] + "\n",
    encoding="utf-8",
)
props.chmod(0o600)

config = '''
    signingConfigs {
        create("shorebirdRelease") {
            val props = java.util.Properties().apply {
                rootProject.file("key.properties").inputStream().use { load(it) }
            }
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
            storeFile = file(props.getProperty("storeFile"))
            storePassword = props.getProperty("storePassword")
        }
    }

'''
content = content.replace("    buildTypes {", config + "    buildTypes {", 1)
content = content.replace(
    'signingConfig = signingConfigs.getByName("debug")',
    'signingConfig = signingConfigs.getByName("shorebirdRelease")',
    1,
)
gradle.write_text(content, encoding="utf-8")
print("Android signing configured using the private release keystore.")
