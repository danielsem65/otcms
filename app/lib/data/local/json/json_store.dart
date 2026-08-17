import 'dart:convert';
import 'dart:io';

import '../../../core/ids.dart';
import '../../../models/audit.dart';
import '../../../models/batch.dart';
import '../../../models/notification.dart';
import '../../../models/product.dart';
import '../../../models/purchase.dart';
import '../../../models/sale.dart';
import '../../../models/settings.dart';
import '../../../models/supplier.dart';
import '../../../models/sync.dart';
import '../../../models/user.dart';
import '../local_store.dart';
import 'json_collection_file.dart';

/// Windows desktop local database: structured JSON files.
///
/// Layout (under the data directory):
///   data/{pharmacy,users,categories,products,suppliers,batches,sales,
///         sale_items,purchases,purchase_items,stock_movements,
///         notifications,audit_log}.json
///   sync/{pending_operations,sync_state,conflicts}.json
///   settings/settings.json
///
/// Writes are atomic (tmp + rename) and per-collection. In-memory maps
/// are the authoritative copy for the session; files are mirrors for
/// persistence and recovery.
class JsonLocalStore implements LocalStore {
  JsonLocalStore({required this.dataDirectory});

  final String dataDirectory;

  String get _dataDir => '$dataDirectory${Platform.pathSeparator}data';
  String get _syncDir => '$dataDirectory${Platform.pathSeparator}sync';
  String get _settingsDir => '$dataDirectory${Platform.pathSeparator}settings';

  late final String _deviceId;

  late final JsonCollectionFile<Product> _products;
  late final JsonCollectionFile<Category> _categories;
  late final JsonCollectionFile<Supplier> _suppliers;
  late final JsonCollectionFile<Batch> _batches;
  late final JsonCollectionFile<Sale> _sales;
  late final JsonCollectionFile<Purchase> _purchases;
  late final JsonCollectionFile<StockMovement> _movements;
  late final JsonCollectionFile<StockCountSession> _countSessions;
  late final JsonCollectionFile<AppNotification> _notifications;
  late final JsonCollectionFile<UserProfile> _users;
  late final JsonCollectionFile<AuditLog> _audit;
  late final JsonCollectionFile<SyncOperation> _operations;
  late final JsonCollectionFile<SyncConflict> _conflicts;

  PharmacyProfile? _pharmacy;
  PharmacySettings _settings = const PharmacySettings();
  SyncState? _syncState;

  @override
  String get deviceId => _deviceId;

  @override
  Future<void> open() async {
    await Directory(_dataDir).create(recursive: true);
    await Directory(_syncDir).create(recursive: true);
    await Directory(_settingsDir).create(recursive: true);

    _deviceId = await _loadOrCreateDeviceId();

    _products = JsonCollectionFile<Product>(
      path: '$_dataDir${Platform.pathSeparator}products.json',
      fromJson: Product.fromJson,
      toJson: (p) => p.toJson(),
    );
    _categories = JsonCollectionFile<Category>(
      path: '$_dataDir${Platform.pathSeparator}categories.json',
      fromJson: Category.fromJson,
      toJson: (c) => c.toJson(),
    );
    _suppliers = JsonCollectionFile<Supplier>(
      path: '$_dataDir${Platform.pathSeparator}suppliers.json',
      fromJson: Supplier.fromJson,
      toJson: (s) => s.toJson(),
    );
    _batches = JsonCollectionFile<Batch>(
      path: '$_dataDir${Platform.pathSeparator}batches.json',
      fromJson: Batch.fromJson,
      toJson: (b) => b.toJson(),
    );
    _sales = JsonCollectionFile<Sale>(
      path: '$_dataDir${Platform.pathSeparator}sales.json',
      fromJson: Sale.fromJson,
      toJson: (s) => s.toJson(),
    );
    _purchases = JsonCollectionFile<Purchase>(
      path: '$_dataDir${Platform.pathSeparator}purchases.json',
      fromJson: Purchase.fromJson,
      toJson: (p) => p.toJson(),
    );
    _movements = JsonCollectionFile<StockMovement>(
      path: '$_dataDir${Platform.pathSeparator}stock_movements.json',
      fromJson: StockMovement.fromJson,
      toJson: (m) => m.toJson(),
    );
    _countSessions = JsonCollectionFile<StockCountSession>(
      path: '$_dataDir${Platform.pathSeparator}stock_counts.json',
      fromJson: StockCountSession.fromJson,
      toJson: (s) => s.toJson(),
    );
    _notifications = JsonCollectionFile<AppNotification>(
      path: '$_dataDir${Platform.pathSeparator}notifications.json',
      fromJson: AppNotification.fromJson,
      toJson: (n) => n.toJson(),
    );
    _users = JsonCollectionFile<UserProfile>(
      path: '$_dataDir${Platform.pathSeparator}users.json',
      fromJson: UserProfile.fromJson,
      toJson: (u) => u.toJson(),
    );
    _audit = JsonCollectionFile<AuditLog>(
      path: '$_dataDir${Platform.pathSeparator}audit_log.json',
      fromJson: AuditLog.fromJson,
      toJson: (a) => a.toJson(),
    );
    _operations = JsonCollectionFile<SyncOperation>(
      path: '$_syncDir${Platform.pathSeparator}pending_operations.json',
      fromJson: SyncOperation.fromJson,
      toJson: (o) => o.toJson(),
    );
    _conflicts = JsonCollectionFile<SyncConflict>(
      path: '$_syncDir${Platform.pathSeparator}conflicts.json',
      fromJson: SyncConflict.fromJson,
      toJson: (c) => c.toJson(),
    );

    // Warm caches.
    await _loadSettings();
    await _loadPharmacy();
    await _loadSyncState();

    // Seed the default pharmacy profile on first run.
    if (_pharmacy == null) {
      final profile = PharmacyProfile(
        id: Ids.newId('pharm'),
        name: _settings.pharmacyName,
        address: _settings.address,
        phone: _settings.phone,
        email: _settings.email,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      await savePharmacy(profile);
    }
  }

  Future<String> _loadOrCreateDeviceId() async {
    final file = File('$_settingsDir${Platform.pathSeparator}device.json');
    if (await file.exists()) {
      try {
        final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final id = map['deviceId'] as String?;
        if (id != null && id.isNotEmpty) return id;
      } catch (_) {}
    }
    final id = Ids.deviceId();
    await file.writeAsString(jsonEncode({'deviceId': id}), flush: true);
    return id;
  }

  Future<void> _loadSettings() async {
    final file = File('$_settingsDir${Platform.pathSeparator}settings.json');
    if (await file.exists()) {
      try {
        final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _settings = PharmacySettings.fromJson(map);
      } catch (_) {}
    }
  }

  Future<void> _loadPharmacy() async {
    final file = File('$_dataDir${Platform.pathSeparator}pharmacy.json');
    if (await file.exists()) {
      try {
        final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _pharmacy = PharmacyProfile.fromJson(map);
      } catch (_) {}
    }
  }

  Future<void> _loadSyncState() async {
    final file = File('$_syncDir${Platform.pathSeparator}sync_state.json');
    if (await file.exists()) {
      try {
        final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _syncState = SyncState.fromJson(map);
      } catch (_) {}
    }
  }

  Future<void> _writeSettingsFile() async {
    final file = File('$_settingsDir${Platform.pathSeparator}settings.json');
    final tmp = File('$_settingsDir${Platform.pathSeparator}settings.json.tmp');
    await tmp.writeAsString(jsonEncode(_settings.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  Future<void> _writePharmacyFile() async {
    if (_pharmacy == null) return;
    final file = File('$_dataDir${Platform.pathSeparator}pharmacy.json');
    final tmp = File('$_dataDir${Platform.pathSeparator}pharmacy.json.tmp');
    await tmp.writeAsString(jsonEncode(_pharmacy!.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  Future<void> _writeSyncStateFile() async {
    if (_syncState == null) return;
    final file = File('$_syncDir${Platform.pathSeparator}sync_state.json');
    final tmp = File('$_syncDir${Platform.pathSeparator}sync_state.json.tmp');
    await tmp.writeAsString(jsonEncode(_syncState!.toJson()), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> close() async {
    await _writeSettingsFile();
    await _writePharmacyFile();
    await _writeSyncStateFile();
    for (final c in [
      _products, _categories, _suppliers, _batches, _sales, _purchases,
      _movements, _countSessions, _notifications, _users, _audit,
      _operations, _conflicts,
    ]) {
      await c.flush();
    }
  }

  // ---------------------------------------------------------------- settings
  @override
  Future<PharmacySettings> getSettings() async => _settings;

  @override
  Future<void> saveSettings(PharmacySettings settings) async {
    _settings = settings;
    await _writeSettingsFile();
  }

  @override
  Future<PharmacyProfile?> getPharmacy() async => _pharmacy;

  @override
  Future<void> savePharmacy(PharmacyProfile pharmacy) async {
    _pharmacy = pharmacy;
    await _writePharmacyFile();
  }

  // ------------------------------------------------------------------- users
  @override
  Future<List<UserProfile>> getUsers() => _users.getAll();

  @override
  Future<UserProfile?> getUserByAuthId(String authUserId) async {
    final users = await _users.getAll();
    for (final u in users) {
      if (u.authUserId == authUserId) return u;
    }
    return null;
  }

  @override
  Future<void> putUser(UserProfile user) => _users.put(user);

  // ---------------------------------------------------------------- products
  @override
  Future<List<Product>> getProducts({String? search, bool activeOnly = false}) async {
    final all = await _products.getAll();
    final query = search?.trim().toUpperCase() ?? '';
    final results = all.where((p) {
      if (activeOnly && !p.active) return false;
      if (query.isEmpty) return true;
      return p.searchTokens.any((token) => token.contains(query));
    }).toList();
    results.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return results;
  }

  @override
  Future<Product?> getProductById(String id) => _products.getById((p) => p.id, id);

  @override
  Future<Product?> getProductByBarcode(String barcode) async {
    final all = await _products.getAll();
    for (final p in all) {
      if (p.barcode != null && p.barcode == barcode) return p;
    }
    return null;
  }

  @override
  Future<void> putProduct(Product product) => _products.put(product);

  @override
  Future<void> putProducts(List<Product> products) => _products.putAll(products);

  // -------------------------------------------------------------- categories
  @override
  Future<List<Category>> getCategories() async {
    final all = await _categories.getAll();
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  @override
  Future<void> putCategory(Category category) => _categories.put(category);

  // --------------------------------------------------------------- suppliers
  @override
  Future<List<Supplier>> getSuppliers() async {
    final all = await _suppliers.getAll();
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  @override
  Future<void> putSupplier(Supplier supplier) => _suppliers.put(supplier);

  // ----------------------------------------------------------------- batches
  @override
  Future<List<Batch>> getBatches({String? productId}) async {
    final all = await _batches.getAll();
    if (productId != null) {
      return all.where((b) => b.productId == productId).toList();
    }
    return all;
  }

  @override
  Future<Batch?> getBatchById(String id) => _batches.getById((b) => b.id, id);

  @override
  Future<void> putBatch(Batch batch) => _batches.put(batch);

  // ------------------------------------------------------------- movements
  @override
  Future<List<StockMovement>> getMovements({String? productId, String? batchId, int? limit}) async {
    var all = await _movements.getAll();
    if (productId != null) all = all.where((m) => m.productId == productId).toList();
    if (batchId != null) all = all.where((m) => m.batchId == batchId).toList();
    all.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
    if (limit != null && all.length > limit) all = all.sublist(0, limit);
    return all;
  }

  @override
  Future<void> putMovement(StockMovement movement) => _movements.put(movement);

  @override
  Future<List<StockMovement>> getMovementsWithStatus(SyncStatus status) async {
    final all = await _movements.getAll();
    return all.where((m) => m.syncStatus == status).toList();
  }

  // ------------------------------------------------------------------- sales
  @override
  Future<void> putSale(Sale sale) => _sales.put(sale);

  @override
  Future<Sale?> getSaleById(String id) => _sales.getById((s) => s.id, id);

  @override
  Future<List<Sale>> getSales({DateTime? from, DateTime? to, int? limit}) async {
    var all = await _sales.getAll();
    if (from != null) all = all.where((s) => !(s.createdAt ?? DateTime(1970)).isBefore(from)).toList();
    if (to != null) all = all.where((s) => !(s.createdAt ?? DateTime(1970)).isAfter(to)).toList();
    all.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
    if (limit != null && all.length > limit) all = all.sublist(0, limit);
    return all;
  }

  @override
  Future<List<Sale>> getSalesWithStatus(SyncStatus status) async {
    final all = await _sales.getAll();
    return all.where((s) => s.syncStatus == status).toList();
  }

  @override
  Future<List<Sale>> getSalesByUser(String userId, {DateTime? from, DateTime? to}) async {
    var all = await _sales.getAll();
    all = all.where((s) => s.userId == userId).toList();
    if (from != null) all = all.where((s) => !(s.createdAt ?? DateTime(1970)).isBefore(from)).toList();
    if (to != null) all = all.where((s) => !(s.createdAt ?? DateTime(1970)).isAfter(to)).toList();
    all.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
    return all;
  }

  @override
  Future<Sale?> getSaleByInvoiceNumber(String invoiceNumber) async {
    final all = await _sales.getAll();
    for (final s in all) {
      if (s.invoiceNumber == invoiceNumber) return s;
    }
    return null;
  }

  @override
  Future<List<Sale>> getDailySales(DateTime day) async {
    final all = await _sales.getAll();
    return all.where((s) {
      final d = s.saleDate ?? s.createdAt;
      if (d == null) return false;
      return d.year == day.year && d.month == day.month && d.day == day.day;
    }).toList();
  }

  // --------------------------------------------------------------- purchases
  @override
  Future<void> putPurchase(Purchase purchase) => _purchases.put(purchase);

  @override
  Future<Purchase?> getPurchaseById(String id) => _purchases.getById((p) => p.id, id);

  @override
  Future<List<Purchase>> getPurchases({int? limit}) async {
    var all = await _purchases.getAll();
    all.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
    if (limit != null && all.length > limit) all = all.sublist(0, limit);
    return all;
  }

  @override
  Future<List<Purchase>> getPurchasesWithStatus(SyncStatus status) async {
    final all = await _purchases.getAll();
    return all.where((p) => p.syncStatus == status).toList();
  }

  // ---------------------------------------------------------- stock counts
  @override
  Future<void> putStockCountSession(StockCountSession session) => _countSessions.put(session);

  @override
  Future<List<StockCountSession>> getStockCountSessions() async {
    final all = await _countSessions.getAll();
    all.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
    return all;
  }

  // ---------------------------------------------------------- notifications
  @override
  Future<List<AppNotification>> getNotifications() async {
    final all = await _notifications.getAll();
    all.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
    return all;
  }

  @override
  Future<List<AppNotification>> getUnreadNotifications() async {
    final all = await _notifications.getAll();
    return all.where((n) => !n.read).toList();
  }

  @override
  Future<void> putNotification(AppNotification notification) => _notifications.put(notification);

  @override
  Future<void> markNotificationRead(String id) async {
    final all = await _notifications.getAll();
    for (final n in all) {
      if (n.id == id && !n.read) {
        await _notifications.put(n.asRead());
      }
    }
  }

  @override
  Future<bool> notificationExists(String dedupKey) async {
    final all = await _notifications.getAll();
    return all.any((n) => n.dedupKey == dedupKey);
  }

  // ------------------------------------------------------------ sync outbox
  @override
  Future<List<SyncOperation>> getOperations({SyncStatus? status}) async {
    final all = await _operations.getAll();
    all.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (status != null) return all.where((o) => o.status == status).toList();
    return all;
  }

  @override
  Future<void> enqueueOperation(SyncOperation operation) => _operations.put(operation);

  @override
  Future<void> updateOperationStatus(String operationId, SyncStatus status,
      {String? lastError}) async {
    final all = await _operations.getAll();
    for (final o in all) {
      if (o.operationId == operationId) {
        await _operations.put(o.copyWith(
          status: status,
          retryCount: status == SyncStatus.failed ? o.retryCount + 1 : o.retryCount,
          lastError: lastError ?? o.lastError,
        ));
      }
    }
  }

  @override
  Future<void> removeOperation(String operationId) async {
    await _operations.removeWhere((o) => o.operationId == operationId);
  }

  @override
  Future<SyncState> getSyncState() async {
    _syncState ??= SyncState(deviceId: deviceId, updatedAt: DateTime.now().toUtc());
    return _syncState!;
  }

  @override
  Future<void> saveSyncState(SyncState state) async {
    _syncState = state;
    await _writeSyncStateFile();
  }

  @override
  Future<List<SyncConflict>> getConflicts() async {
    final all = await _conflicts.getAll();
    all.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
    return all;
  }

  @override
  Future<void> addConflict(SyncConflict conflict) => _conflicts.put(conflict);

  // ------------------------------------------------------------------ audit
  @override
  Future<void> logAudit(AuditLog entry) => _audit.put(entry);

  @override
  Future<List<AuditLog>> getAuditLogs({int? limit}) async {
    var all = await _audit.getAll();
    all.sort((a, b) => (b.createdAt ?? DateTime(1970)).compareTo(a.createdAt ?? DateTime(1970)));
    if (limit != null && all.length > limit) all = all.sublist(0, limit);
    return all;
  }

  // ---------------------------------------------------------------- backups
  @override
  Future<Map<String, List<Map<String, dynamic>>>> exportAll() async {
    return {
      'products': (await _products.getAll()).map((e) => e.toJson()).toList(),
      'categories': (await _categories.getAll()).map((e) => e.toJson()).toList(),
      'suppliers': (await _suppliers.getAll()).map((e) => e.toJson()).toList(),
      'batches': (await _batches.getAll()).map((e) => e.toJson()).toList(),
      'sales': (await _sales.getAll()).map((e) => e.toJson()).toList(),
      'purchases': (await _purchases.getAll()).map((e) => e.toJson()).toList(),
      'stock_movements': (await _movements.getAll()).map((e) => e.toJson()).toList(),
      'stock_counts': (await _countSessions.getAll()).map((e) => e.toJson()).toList(),
      'notifications': (await _notifications.getAll()).map((e) => e.toJson()).toList(),
      'users': (await _users.getAll()).map((e) => e.toJson()).toList(),
      'audit_log': (await _audit.getAll()).map((e) => e.toJson()).toList(),
      'pending_operations': (await _operations.getAll()).map((e) => e.toJson()).toList(),
      'conflicts': (await _conflicts.getAll()).map((e) => e.toJson()).toList(),
    };
  }

  @override
  Future<void> importAll(Map<String, List<Map<String, dynamic>>> snapshot) async {
    Future<void> putByKey(JsonCollectionFile c, String key) {
      final items = snapshot[key];
      if (items == null) return Future.value();
      return c.replaceAll(items.map((e) => c.fromJson(e)).toList());
    }

    await putByKey(_products, 'products');
    await putByKey(_categories, 'categories');
    await putByKey(_suppliers, 'suppliers');
    await putByKey(_batches, 'batches');
    await putByKey(_sales, 'sales');
    await putByKey(_purchases, 'purchases');
    await putByKey(_movements, 'stock_movements');
    await putByKey(_countSessions, 'stock_counts');
    await putByKey(_notifications, 'notifications');
    await putByKey(_users, 'users');
    await putByKey(_audit, 'audit_log');
    await putByKey(_operations, 'pending_operations');
    await putByKey(_conflicts, 'conflicts');
  }
}