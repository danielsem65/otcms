import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase bootstrap (auth + data client).
///
/// Initialized only when credentials are configured; otherwise the app
/// runs in local mode with no network dependency.
class SupabaseBootstrap {
  SupabaseBootstrap._();

  static bool _initialized = false;

  static Future<SupabaseClient> initialize() async {
    if (_initialized) return Supabase.instance.client;
    await Supabase.initialize(
      url: _url,
      publishableKey: _anonKey,
    );
    _initialized = true;
    return Supabase.instance.client;
  }

  static String get _url => const String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: '',
      );

  static String get _anonKey => const String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue: '',
      );

  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;

  static bool get isInitialized => _initialized;
}