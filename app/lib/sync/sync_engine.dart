import 'dart:async';
import 'dart:math';

import '../core/ids.dart';
import '../core/result.dart';
import '../data/local/local_store.dart';
import '../data/remote/supabase_repo.dart';
import '../models/audit.dart';
import '../models/batch.dart';
import '../models/product.dart';
import '../models/purchase.dart';
import '../models/sale.dart';
import '../models/sync.dart';
import 'connectivity_service.dart';

/// Sync engine — the bridge between local data and Supabase.
///
/// Upload (outbox):
///   1. every local mutation enqueues a [SyncOperation]
///   2. when online, operations drain in order of creation
///   3. each operation is pushed through an idempotent server RPC
///   4. OK / DUPLICATE → SYNCED; validation error → CONFLICT + record;
///      network failure → retry with backoff (max attempts → FAILED)
///
/// Download:
///   5. after the queue drains, pull changes since `lastPulledAt`
///   6. upsert into the local store and advance the sync point
///
/// Idempotency is guaranteed by the server via operation ids — the same
/// operation can never create duplicate data, even over flaky networks.
class SyncEngine {
  SyncEngine({
    required LocalStore store,
    required SupabaseRepo repo,
    required ConnectivityService connectivity,
    this.logAudit,
  });

  final LocalStore store;
  final SupabaseRepo repo;
  final ConnectivityService connectivity;
  final Future<void> Function(AuditLog entry)? logAudit;

  static const _maxRetries = 5;
  static const _baseBackoff = Duration(seconds: 3);

  final _stateController = StreamController<SyncStateEvent>.broadcast();
  Stream<SyncStateEvent> get stateStream => _stateController.stream;

  SyncStateEvent _last = const SyncStateEvent(SyncPhase.idle, 0);
  SyncStateEvent get lastEvent => _last;

  bool _running = false;
  Timer? _retryTimer;
  final _lock = <Future<void> Function()>[];
  bool _draining = false;

  /// Enqueues an operation for an entity already written to the local
  /// store. [entityType] values come from [EntityTypes].
  Future<void> enqueue({
    required String entityType,
    required String entityId,
    String operationType = 'CREATE',
    Map<String, dynamic> payload = const {},
  }) async {
    final state = await store.getSyncState();
    final op = SyncOperation(
      operationId: Ids.operationId(),
      deviceId: store.deviceId,
      entityType: entityType,
      entityId: entityId,
      operationType: operationType,
      createdAt: DateTime.now().toUtc(),
      payload: payload,
    );
    await store.enqueueOperation(op);
    _emit(SyncStateEvent(SyncPhase.pending, (await store.getOperations(status: SyncStatus.pending)).length));
    _kick();
    return;
  }

  void _kick() {
    if (connectivity.status.isOnline) {
      _retryTimer?.cancel();
      _retryTimer = Timer(Duration(seconds: 1), () => runOnce());
    }
  }

  Future<void> onConnectivityChanged(ConnectionStatus status) async {
    if (status.isOnline) {
      await runOnce();
    } else {
      _emit(const SyncStateEvent(SyncPhase.offline, 0));
    }
  }

  /// One full sync cycle: push outbox then pull changes.
  Future<SyncResult> runOnce() async {
    if (!repo.isConfigured) {
      _emit(const SyncStateEvent(SyncPhase.localOnly, 0));
      return const SyncResult.ok(0, 0);
    }
    if (!repo.hasSession) {
      _emit(const SyncStateEvent(SyncPhase.needsAuth, 0));
      return const SyncResult.ok(0, 0);
    }
    if (_running) return const SyncResult.ok(0, 0);
    _running = true;
    try {
      await logAudit?.call(AuditLog(
        id: Ids.auditId(),
        action: AuditLog.syncStarted,
        createdAt: DateTime.now().toUtc(),
      ));
      final pushed = await _pushOutbox();
      final pulled = await _pullChanges();
      _emit(SyncStateEvent(SyncPhase.synced, 0));
      await logAudit?.call(AuditLog(
        id: Ids.auditId(),
        action: AuditLog.syncCompleted,
        after: {'pushed': pushed, 'pulled': pulled},
        createdAt: DateTime.now().toUtc(),
      ));
      return SyncResult.ok(pushed, pulled);
    } catch (e) {
      _emit(const SyncStateEvent(SyncPhase.error, 0));
      await logAudit?.call(AuditLog(
        id: Ids.auditId(),
        action: AuditLog.syncFailed,
        after: {'error': e.toString()},
        createdAt: DateTime.now().toUtc(),
      ));
      _scheduleRetry();
      return SyncResult.failed(e.toString());
    } finally {
      _running = false;
    }
  }

  // -------------------------------------------------------------- push outbox

  Future<int> _pushOutbox() async {
    final pending = await store.getOperations(status: SyncStatus.pending);
    var pushed = 0;
    for (final op in pending) {
      await store.updateOperationStatus(op.operationId, SyncStatus.syncing);
      _emit(SyncStateEvent(SyncPhase.syncing, pending.length - pushed));
      final outcome = await _pushOperation(op);
      switch (outcome) {
        case PushOutcome.success:
          await store.removeOperation(op.operationId);
          _markEntitySynced(op);
          pushed++;
        case PushOutcome.duplicate:
          await store.removeOperation(op.operationId);
          _markEntitySynced(op);
          pushed++;
        case PushOutcome.conflict:
          await store.updateOperationStatus(
            op.operationId,
            SyncStatus.conflict,
            lastError: 'conflict',
          );
          await store.addConflict(SyncConflict(
            id: Ids.newId('conflict'),
            organizationId: null,
            operationId: op.operationId,
            entityType: op.entityType,
            entityId: op.entityId,
            reason: 'Server rejected this operation',
            payload: op.payload,
            createdAt: DateTime.now().toUtc(),
          ));
          pushed++;
        case PushOutcome.retryable:
          final next = op.retryCount + 1;
          if (next >= _maxRetries) {
            await store.updateOperationStatus(op.operationId, SyncStatus.failed,
                lastError: 'max retries');
          } else {
            await store.updateOperationStatus(op.operationId, SyncStatus.pending,
                lastError: 'retry $next');
            await Future.delayed(_backoffFor(next));
          }
      }
    }
    return pushed;
  }

  Duration _backoffFor(int attempt) {
    final exp = min(attempt.toDouble(), 5);
    return Duration(milliseconds: (_baseBackoff.inMilliseconds * pow(2, exp)).round());
  }

  Future<PushOutcome> _pushOperation(SyncOperation op) async {
    try {
      final Map<String, dynamic> response;
      switch (op.entityType) {
        case EntityTypes.sale:
          response = await repo.syncSale(op.payload);
        case EntityTypes.stockMovement:
          response = await repo.syncMovement(op.payload);
        case EntityTypes.purchase:
          response = await repo.syncPurchaseReceipt(op.payload);
        case EntityTypes.product:
          response = await repo.syncUpsert('product', op.payload);
        case EntityTypes.category:
          response = await repo.syncUpsert('category', op.payload);
        case EntityTypes.supplier:
          response = await repo.syncUpsert('supplier', op.payload);
        case EntityTypes.notification:
          response = await repo.syncUpsert('notification', op.payload);
        case EntityTypes.audit:
          response = await repo.syncUpsert('audit', op.payload);
        default:
          response = await repo.syncUpsert(op.entityType.toLowerCase(), op.payload);
      }
      final status = (response['status'] as String?) ?? 'ERROR';
      if (status == 'OK' || status == 'DUPLICATE') return PushOutcome.success;
      if (status == 'INVOICE_COLLISION') {
        return PushOutcome.conflict;
      }
      if (status == 'ERROR') {
        final message = (response['message'] as String?) ?? 'server error';
        if (message.contains('permission') || message.contains('expired')) {
          return PushOutcome.conflict;
        }
        return PushOutcome.retryable;
      }
      return PushOutcome.retryable;
    } catch (e) {
      return PushOutcome.retryable;
    }
  }

  void _markEntitySynced(SyncOperation op) {
    switch (op.entityType) {
      case EntityTypes.sale:
        _updateSaleStatus(op.entityId, SyncStatus.synced);
      case EntityTypes.stockMovement:
        _updateMovementStatus(op.entityId, SyncStatus.synced);
      case EntityTypes.purchase:
        _updatePurchaseStatus(op.entityId, SyncStatus.synced);
    }
  }

  Future<void> _updateSaleStatus(String id, SyncStatus status) async {
    final sale = await store.getSaleById(id);
    if (sale == null) return;
    final updated = Sale(
      id: sale.id,
      operationId: sale.operationId,
      invoiceNumber: sale.invoiceNumber,
      userId: sale.userId,
      sellerName: sale.sellerName,
      deviceId: sale.deviceId,
      branchId: sale.branchId,
      organizationId: sale.organizationId,
      saleDate: sale.saleDate,
      saleTime: sale.saleTime,
      createdAt: sale.createdAt,
      totalAmountPesewas: sale.totalAmountPesewas,
      items: sale.items,
      syncStatus: status,
    );
    await store.putSale(updated);
  }

  Future<void> _updateMovementStatus(String id, SyncStatus status) async {
    final all = await store.getMovements();
    for (final m in all) {
      if (m.id == id) {
        await store.putMovement(StockMovement(
          id: m.id,
          operationId: m.operationId,
          productId: m.productId,
          batchId: m.batchId,
          quantity: m.quantity,
          movementType: m.movementType,
          referenceId: m.referenceId,
          reason: m.reason,
          userId: m.userId,
          branchId: m.branchId,
          organizationId: m.organizationId,
          createdAt: m.createdAt,
          syncStatus: status,
        ));
      }
    }
  }

  Future<void> _updatePurchaseStatus(String id, SyncStatus status) async {
    final purchase = await store.getPurchaseById(id);
    if (purchase == null) return;
    await store.putPurchase(Purchase(
      id: purchase.id,
      operationId: purchase.operationId,
      organizationId: purchase.organizationId,
      branchId: purchase.branchId,
      supplierId: purchase.supplierId,
      purchaseNumber: purchase.purchaseNumber,
      status: purchase.status,
      totalCostPesewas: purchase.totalCostPesewas,
      receivedAt: purchase.receivedAt,
      userId: purchase.userId,
      createdAt: purchase.createdAt,
      updatedAt: purchase.updatedAt,
      items: purchase.items,
      syncStatus: status,
    ));
  }

  // --------------------------------------------------------------- pull

  Future<int> _pullChanges() async {
    final state = await store.getSyncState();
    final response = await repo.pullAllChanges(state.lastPulledAt);
    if ((response['status'] as String?) != 'OK') return 0;

    int count = 0;
    count += await _upsertProducts(response['products']);
    count += await _upsertCategories(response['categories']);
    count += await _upsertSuppliers(response['suppliers']);
    count += await _upsertBatches(response['batches']);
    count += await _upsertSales(response['sales'], response['saleItems']);
    count += await _upsertPurchases(response['purchases'], response['purchaseItems']);
    count += await _upsertMovements(response['stockMovements']);
    count += await _upsertNotifications(response['notifications']);
    count += await _upsertConflicts(response['conflicts']);

    final now = DateTime.now().toUtc();
    final updatedState = state.copyWith(
      lastPushedAt: now,
      lastPulledAt: now,
      updatedAt: now,
    );
    await store.saveSyncState(updatedState);
    if (repo.isConfigured) {
      await repo.updateSyncPoint(store.deviceId, now, now);
    }
    return count;
  }

  Future<int> _upsertProducts(dynamic raw) async {
    if (raw is! List) return 0;
    final items = raw.whereType<Map<String, dynamic>>().toList();
    if (items.isEmpty) return 0;
    final products = items.map((e) => Product.fromJson(_snakeToCamel(e))).toList();
    await store.putProducts(products);
    return products.length;
  }

  Future<int> _upsertCategories(dynamic raw) async {
    if (raw is! List) return 0;
    final items = raw.whereType<Map<String, dynamic>>().toList();
    if (items.isEmpty) return 0;
    for (final e in items) {
      await store.putCategory(Category.fromJson(_snakeToCamel(e)));
    }
    return items.length;
  }

  Future<int> _upsertSuppliers(dynamic raw) async {
    if (raw is! List) return 0;
    final items = raw.whereType<Map<String, dynamic>>().toList();
    if (items.isEmpty) return 0;
    for (final e in items) {
      await store.putSupplier(Supplier.fromJson(_snakeToCamel(e)));
    }
    return items.length;
  }

  Future<int> _upsertBatches(dynamic raw) async {
    if (raw is! List) return 0;
    final items = raw.whereType<Map<String, dynamic>>().toList();
    if (items.isEmpty) return 0;
    for (final e in items) {
      await store.putBatch(Batch.fromJson(_snakeToCamel(e)));
    }
    return items.length;
  }

  Future<int> _upsertSales(dynamic rawSales, dynamic rawItems) async {
    if (rawSales is! List) return 0;
    final sales = rawSales.whereType<Map<String, dynamic>>().toList();
    final itemsBySale = <String, List<Map<String, dynamic>>>{};
    if (rawItems is List) {
      for (final e in rawItems.whereType<Map<String, dynamic>>()) {
        final saleId = e['sale_id'] as String? ?? e['saleId'] as String?;
        if (saleId == null) continue;
        itemsBySale.putIfAbsent(saleId, () => []).add(e);
      }
    }
    for (final e in sales) {
      final saleJson = _snakeToCamel(e);
      final saleId = saleJson['id'] as String;
      final items = (itemsBySale[saleId] ?? []).map(_snakeToCamel).toList();
      final local = await store.getSaleById(saleId);
      // Never overwrite a locally pending sale that the server already
      // accepted — it is the same sale (idempotency).
      if (local != null && local.syncStatus != SyncStatus.synced) continue;
      await store.putSale(Sale.fromJson({
        ...saleJson,
        'items': items,
        'syncStatus': 'SYNCED',
      }));
    }
    return sales.length;
  }

  Future<int> _upsertPurchases(dynamic rawPurchases, dynamic rawItems) async {
    if (rawPurchases is! List) return 0;
    final purchases = rawPurchases.whereType<Map<String, dynamic>>().toList();
    final itemsByPurchase = <String, List<Map<String, dynamic>>>{};
    if (rawItems is List) {
      for (final e in rawItems.whereType<Map<String, dynamic>>()) {
        final id = e['purchase_id'] as String? ?? e['purchaseId'] as String?;
        if (id == null) continue;
        itemsByPurchase.putIfAbsent(id, () => []).add(e);
      }
    }
    for (final e in purchases) {
      final json = _snakeToCamel(e);
      final id = json['id'] as String;
      final items = (itemsByPurchase[id] ?? []).map(_snakeToCamel).toList();
      final local = await store.getPurchaseById(id);
      if (local != null && local.syncStatus != SyncStatus.synced) continue;
      await store.putPurchase(Purchase.fromJson({...json, 'items': items, 'syncStatus': 'SYNCED'}));
    }
    return purchases.length;
  }

  Future<int> _upsertMovements(dynamic raw) async {
    if (raw is! List) return 0;
    final items = raw.whereType<Map<String, dynamic>>().toList();
    if (items.isEmpty) return 0;
    for (final e in items) {
      final json = _snakeToCamel(e);
      final id = json['id'] as String;
      // Movements are immutable; skip if already present.
      final existing = await store.getMovements();
      if (existing.any((m) => m.id == id)) continue;
      await store.putMovement(StockMovement.fromJson({...json, 'syncStatus': 'SYNCED'}));
    }
    return items.length;
  }

  Future<int> _upsertNotifications(dynamic raw) async {
    if (raw is! List) return 0;
    final items = raw.whereType<Map<String, dynamic>>().toList();
    if (items.isEmpty) return 0;
    for (final e in items) {
      await store.putNotification(AppNotification.fromJson(_snakeToCamel(e)));
    }
    return items.length;
  }

  Future<int> _upsertConflicts(dynamic raw) async {
    if (raw is! List) return 0;
    final items = raw.whereType<Map<String, dynamic>>().toList();
    if (items.isEmpty) return 0;
    for (final e in items) {
      await store.addConflict(SyncConflict.fromJson(_snakeToCamel(e)));
    }
    return items.length;
  }

  /// Converts server `snake_case` keys to client `camelCase` keys.
  Map<String, dynamic> _snakeToCamel(Map<String, dynamic> source) {
    final out = <String, dynamic>{};
    source.forEach((key, value) {
      final parts = key.split('_');
      final camel = parts.first +
          parts.skip(1).map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1)).join();
      out[camel] = value;
    });
    return out;
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 15), () {
      if (connectivity.status.isOnline) runOnce();
    });
  }

  void _emit(SyncStateEvent event) {
    _last = event;
    if (!_stateController.isClosed) _stateController.add(event);
  }

  void dispose() {
    _retryTimer?.cancel();
    _stateController.close();
  }
}

enum SyncPhase {
  idle,
  localOnly,
  offline,
  pending,
  syncing,
  synced,
  error,
  needsAuth,
}

class SyncStateEvent {
  const SyncStateEvent(this.phase, this.pendingCount);
  final SyncPhase phase;
  final int pendingCount;
}

enum PushOutcome { success, duplicate, conflict, retryable }

class SyncResult {
  const SyncResult.ok(this.pushed, this.pulled) : error = null;
  const SyncResult.failed(this.error) : pushed = 0, pulled = 0;

  final int pushed;
  final int pulled;
  final String? error;

  bool get isOk => error == null;
}
