import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'screens/app_shell.dart';

/// OTCMS root widget.
class OtcmsApp extends ConsumerWidget {
  const OtcmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;

    return MaterialApp(
      title: 'OTCMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00897B)),
        scaffoldBackgroundColor: const Color(0xFFF7F9F9),
      ),
      home: const AppShell(),
      locale: const Locale('en'),
    );
  }
}
