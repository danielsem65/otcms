import '../../models/audit.dart';
import '../../models/batch.dart';
import '../../models/notification.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/sale.dart';
import '../../models/settings.dart';
import '../../models/supplier.dart';
import '../../models/sync.dart';
import '../../models/user.dart';

/// Local persistence contract.
///
/// Two implementations exist:
///  * [JsonLocalStore] (Windows desktop) — structured JSON files, atomic
///    writes, per-collection persistence (never one giant blob).
///  * SqfliteLocalStore (Android) — SQLite cache, same contract.
///
/// The sync engine and all services depend only on this interface, which
/// keeps behavior identical across platforms.
abstract class LocalStore {
  /// Opens the store, creating the data layout if needed.
  Future<void> open();

  Future<void> close();

  String get deviceId;

  // ---------------------------------------------------------------- settings
  Future<PharmacySettings> getSettings();
  Future<void> saveSettings(PharmacySettings settings);
  Future<PharmacyProfile?> getPharmacy();
  Future<void> savePharmacy(PharmacyProfile pharmacy);

  // ------------------------------------------------------------------- users
  Future<List<UserProfile>> getUsers();
  Future<UserProfile?> getUserByAuthId(String authUserId);
  Future<void> putUser(UserProfile user);

  // ---------------------------------------------------------------- products
  /// Full catalog, optionally filtered by a search term
  /// (name, generic, brand, barcode, sku — case-insensitive).
  Future<List<Product>> getProducts({String? search, bool activeOnly = false});
  Future<Product?> getProductById(String id);
  Future<Product?> getProductByBarcode(String barcode);
  Future<void> putProduct(Product product);
  Future<void> putProducts(List<Product> products);

  // -------------------------------------------------------------- categories
  Future<List<Category>> getCategories();
  Future<void> putCategory(Category category);

  // --------------------------------------------------------------- suppliers
  Future<List<Supplier>> getSuppliers();
  Future<void> putSupplier(Supplier supplier);

  // ----------------------------------------------------------------- batches
  Future<List<Batch>> getBatches({String? productId});
  Future<Batch?> getBatchById(String id);
  Future<void> putBatch(Batch batch);

  // ------------------------------------------------------------- movements
  Future<List<StockMovement>> getMovements({String? productId, String? batchId, int? limit});
  Future<void> putMovement(StockMovement movement);

  /// Movements that have not been confirmed by the server yet.
  Future<List<StockMovement>> getMovementsWithStatus(SyncStatus status);

  // ------------------------------------------------------------------- sales
  Future<void> putSale(Sale sale);
  Future<Sale?> getSaleById(String id);
  Future<List<Sale>> getSales({DateTime? from, DateTime? to, int? limit});
  Future<List<Sale>> getSalesWithStatus(SyncStatus status);
  Future<List<Sale>> getSalesByUser(String userId, {DateTime? from, DateTime? to});
  Future<Sale?> getSaleByInvoiceNumber(String invoiceNumber);

  /// Sales whose saleDate falls in the given local day range.
  Future<List<Sale>> getDailySales(DateTime day);

  // --------------------------------------------------------------- purchases
  Future<void> putPurchase(Purchase purchase);
  Future<Purchase?> getPurchaseById(String id);
  Future<List<Purchase>> getPurchases({int? limit});
  Future<List<Purchase>> getPurchasesWithStatus(SyncStatus status);

  // ---------------------------------------------------------- stock counts
  Future<void> putStockCountSession(StockCountSession session);
  Future<List<StockCountSession>> getStockCountSessions();

  // ---------------------------------------------------------- notifications
  Future<List<AppNotification>> getNotifications();
  Future<List<AppNotification>> getUnreadNotifications();
  Future<void> putNotification(AppNotification notification);
  Future<void> markNotificationRead(String id);
  Future<bool> notificationExists(String dedupKey);

  // ------------------------------------------------------------ sync outbox
  Future<List<SyncOperation>> getOperations({SyncStatus? status});
  Future<void> enqueueOperation(SyncOperation operation);
  Future<void> updateOperationStatus(String operationId, SyncStatus status, {String? lastError});
  Future<void> removeOperation(String operationId);
  Future<SyncState> getSyncState();
  Future<void> saveSyncState(SyncState state);
  Future<List<SyncConflict>> getConflicts();
  Future<void> addConflict(SyncConflict conflict);

  // ------------------------------------------------------------------ audit
  Future<void> logAudit(AuditLog entry);
  Future<List<AuditLog>> getAuditLogs({int? limit});

  // ---------------------------------------------------------------- backups
  /// Full local snapshot as a map of collectionName -> json-encoded list.
  /// The JSON store also snapshots its raw files directly.
  Future<Map<String, List<Map<String, dynamic>>>> exportAll();

  /// Replaces local collections from a snapshot (used by restore).
  Future<void> importAll(Map<String, List<Map<String, dynamic>>> snapshot);
}

/// Entity type names shared with the sync engine and the cloud.
class EntityTypes {
  static const sale = 'SALE';
  static const stockMovement = 'STOCK_MOVEMENT';
  static const purchase = 'PURCHASE';
  static const product = 'PRODUCT';
  static const category = 'CATEGORY';
  static const supplier = 'SUPPLIER';
  static const batch = 'BATCH';
  static const profile = 'PROFILE';
  static const notification = 'NOTIFICATION';
  static const audit = 'AUDIT';
  static const stockCount = 'STOCK_COUNT';
}
