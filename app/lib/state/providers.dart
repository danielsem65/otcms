import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/local/local_store.dart';
import '../data/local/local_store_factory.dart';
import '../data/remote/supabase_bootstrap.dart';
import '../data/remote/supabase_repo.dart';
import '../models/settings.dart';
import '../models/user.dart';
import '../services/audit_service.dart';
import '../services/auth_service.dart';
import '../services/product_import_service.dart';
import '../sync/connectivity_service.dart';
import '../sync/sync_engine.dart';

/// The opened local store — injected at startup (see `main.dart`) or
/// overridden in tests.
final localStoreProvider = Provider<LocalStore>((ref) {
  throw StateError('localStoreProvider not overridden at startup.');
});

final settingsProvider = FutureProvider<PharmacySettings>((ref) async {
  final store = ref.watch(localStoreProvider);
  return store.getSettings();
});

final pharmacyProvider = FutureProvider<PharmacyProfile?>((ref) async {
  final store = ref.watch(localStoreProvider);
  return store.getPharmacy();
});

final connectivityProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  service.start();
  ref.onDispose(service.dispose);
  return service;
});

final supabaseRepoProvider = Provider<SupabaseRepo>((ref) => SupabaseRepo());

final auditServiceProvider = Provider<AuditService>((ref) {
  return AuditService(store: ref.watch(localStoreProvider));
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(localStore: ref.watch(localStoreProvider));
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  final engine = SyncEngine(
    store: ref.watch(localStoreProvider),
    repo: ref.watch(supabaseRepoProvider),
    connectivity: connectivity,
  );
  final sub = connectivity.stream.listen(engine.onConnectivityChanged);
  ref.onDispose(() {
    sub.cancel();
    engine.dispose();
  });
  return engine;
});

final productImportServiceProvider = Provider<ProductImportService>((ref) {
  return ProductImportService(
    store: ref.watch(localStoreProvider),
    audit: ref.watch(auditServiceProvider),
  );
});

/// Current signed-in user (local Administrator in local mode).
final currentUserProvider = FutureProvider<UserProfile>((ref) async {
  final store = ref.watch(localStoreProvider);
  return AuthService(localStore: store).currentUser();
});

/// Live sync state (phase + pending count).
final syncStateStreamProvider = StreamProvider<SyncStateEvent>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.stateStream;
});

final hasSupabaseProvider = Provider<bool>((ref) => SupabaseBootstrap.isConfigured);

/// Resolves the local data directory.
///
/// Desktop: `<documents>/OTCMS` (configurable via settings).
/// Android: `<app support dir>/otcms`.
Future<String> resolveDataDirectory() async {
  if (Platform.isWindows) {
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}${Platform.pathSeparator}OTCMS';
  }
  final support = await getApplicationSupportDirectory();
  return support.path;
}

/// Opens the platform store (used by main / tests).
Future<LocalStore> openStore({String? dataDirectory}) async {
  final dir = dataDirectory ?? await resolveDataDirectory();
  final store = createLocalStore(dataDirectory: dir);
  await store.open();
  return store;
}
