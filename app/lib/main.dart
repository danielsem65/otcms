import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/remote/supabase_bootstrap.dart';
import 'state/providers.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (SupabaseBootstrap.isConfigured) {
    await SupabaseBootstrap.initialize();
  }
  final store = await openStore();
  runApp(
    ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const OtcmsApp(),
    ),
  );
}