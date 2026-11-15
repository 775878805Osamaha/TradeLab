# Shorebird OTA setup — TradeLab

**Status: preparation only.** This PR does not publish a patch or modify devices.
The workflow is disabled for pushes unless the repository variable `SHOREBIRD_AUTO_PATCH` is set to `true`.

1. Register an account at https://console.shorebird.dev/ (free tier is available).
2. From an authenticated machine, prepare a generated Android host as used in the repository's current CI, enter `flutter_app`, run `shorebird login` then `shorebird init`. Commit the real `flutter_app/shorebird.yaml` and changed `flutter_app/pubspec.yaml` to the repo. Never invent an app_id.
3. Create or reuse a **stable private Android release keystore**. Store it only in GitHub repository Actions secrets, base64-encoded as `SHOREBIRD_ANDROID_KEYSTORE_BASE64`, with `SHOREBIRD_ANDROID_STORE_PASSWORD`, `SHOREBIRD_ANDROID_KEY_ALIAS`, `SHOREBIRD_ANDROID_KEY_PASSWORD`. Securely back up the keystore/passwords. **Never reuse a new key if you need an in-place upgrade of the existing signed app.** Installing an APK signed with a different key may require uninstalling and can erase local data.
4. In Shorebird Console create a service account API key and add repository Actions secret `SHOREBIRD_TOKEN`. Never paste this token into code, a PR, or the chat. Shorebird's old login:ci tokens are no longer valid.
5. Confirm the Flutter preview app's Android package name and OAuth callback before using it as the updateable app; its package name may differ from the older native TradeLab app. Never install a conflicting package or overwrite local trade data without backup.
6. After merging, open GitHub Actions → **Shorebird Android OTA** → Run workflow → select **release**. Once it succeeds, install the actual signed `Shorebird-Android-Base-APK` artifact on a test device. Do not use the older standard Flutter APK as the OTA baseline.
7. Copy the *exact* release version (for example `0.1.0+1`) into repository Actions variable `SHOREBIRD_RELEASE_VERSION`. Run **patch** manually with a small Dart-only test change and verify that it downloads on one app launch and takes effect on the next cold launch.
8. Only after device verification, set repository Actions variable `SHOREBIRD_AUTO_PATCH` to `true`. Subsequent pushes to main changing Flutter Dart sources will trigger patch publication if checks pass. Keep repository branch protections/reviews on main.

Native Android changes, Flutter engine changes, new fonts/images and native plugin changes require a new signed release APK. The baseline app must be Shorebird-built. For accounting/customer data, preserve backups and verify signing certificates before upgrading.

Docs: https://docs.shorebird.dev/code-push/ci/github/ and https://docs.shorebird.dev/code-push/release/
