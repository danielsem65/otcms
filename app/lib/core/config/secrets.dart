/// Local secrets for development builds.
///
/// Fill these in ONLY if you are not passing values via
/// `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
///
/// The ANON key is public by design; never put the service-role key here.
library;

const secrets = _Secrets(
  supabaseUrl: '',
  supabaseAnonKey: '',
);

class _Secrets {
  const _Secrets({required this.supabaseUrl, required this.supabaseAnonKey});

  final String supabaseUrl;
  final String supabaseAnonKey;
}
