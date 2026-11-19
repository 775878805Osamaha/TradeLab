import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Appearance is a device-local preference, not a broker/account property.
/// TradeLab never uses this value for market data, orders or chart history.
abstract class ThemePreferenceStore {
  /// Null means no saved preference (or an unrecognized older value).
  Future<bool?> loadDarkMode();
  Future<void> saveDarkMode(bool enabled);
}

/// Uses the secure, app-private storage already shipped for cTrader OAuth.
/// A separate key means appearance never touches credentials or accounts.
class SecureThemePreferenceStore implements ThemePreferenceStore {
  SecureThemePreferenceStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const key = 'tradelab_flutter_appearance_dark_mode_v1';

  @override
  Future<bool?> loadDarkMode() async {
    final stored = await _storage.read(key: key);
    return switch (stored) {
      'dark' => true,
      'light' => false,
      _ => null,
    };
  }

  @override
  Future<void> saveDarkMode(bool enabled) =>
      _storage.write(key: key, value: enabled ? 'dark' : 'light');
}
