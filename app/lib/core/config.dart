import 'config/secrets.dart' as local;

/// Application configuration.
///
/// Supabase credentials are injected at build time via `--dart-define`
/// (GitHub Actions secrets), falling back to the local `secrets.dart`
/// which contains empty defaults. A service-role key must never appear
/// here or anywhere in the app.
class AppConfig {
  AppConfig._();

  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: local.secrets.supabaseUrl);

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: local.secrets.supabaseAnonKey);
  /// True when cloud credentials are configured; otherwise the app runs
  /// in fully local mode (no auth required, no sync).
  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Default pharmacy name before setup.
  static const String defaultPharmacyName = 'Agya Appiah OTCMS';

  static const String defaultCurrencyCode = 'GHS';
  static const String defaultCurrencySymbol = '₵';
  static const String defaultTimezone = 'Africa/Accra';
}
