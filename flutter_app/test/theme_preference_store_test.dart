import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tradelab_flutter/data/theme_preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dark and light survive independent secure storage reopen', () async {
    FlutterSecureStorage.setMockInitialValues({
      'tradelab_flutter_ctrader_session': 'existing-session',
    });
    const underlying = FlutterSecureStorage();
    final first = SecureThemePreferenceStore(storage: underlying);
    expect(await first.loadDarkMode(), isNull);
    await first.saveDarkMode(true);
    final reopened = SecureThemePreferenceStore(storage: underlying);
    expect(await reopened.loadDarkMode(), isTrue);
    await reopened.saveDarkMode(false);
    final again = SecureThemePreferenceStore(storage: underlying);
    expect(await again.loadDarkMode(), isFalse);
    expect(await underlying.read(key: 'tradelab_flutter_ctrader_session'),
        'existing-session',
        reason: 'Appearance must not alter broker credentials');
  });

  test('unexpected stored appearance value is not treated as dark', () async {
    FlutterSecureStorage.setMockInitialValues({
      SecureThemePreferenceStore.key: 'invalid-preference',
    });
    expect(await SecureThemePreferenceStore().loadDarkMode(), isNull);
  });
}
