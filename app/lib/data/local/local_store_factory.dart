import 'dart:io';

import 'json/json_store.dart';
import 'local_store.dart';

/// Platform-aware local store selection:
///  * Android → SQLite cache (implemented in the mobile sync phase).
///  * Desktop/tests → structured JSON store.
LocalStore createLocalStore({String? dataDirectory}) {
  if (Platform.isAndroid) {
    // The SQLite cache store is initialized via `open()` on a path from
    // path_provider; until then a JSON store keeps the app bootable.
    // (sqflite store wired in the mobile cache phase.)
    final dir = dataDirectory ?? '.';
    return JsonLocalStore(dataDirectory: dir);
  }
  return JsonLocalStore(dataDirectory: dataDirectory ?? '.');
}