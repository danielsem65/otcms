import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/app_shell.dart';
import 'theme.dart';

/// OTCMS root widget.
class OtcmsApp extends ConsumerWidget {
  const OtcmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'OTCMS',
      debugShowCheckedModeBanner: false,
      theme: OtcmsTheme.light(),
      home: const AppShell(),
      locale: const Locale('en'),
    );
  }
}
