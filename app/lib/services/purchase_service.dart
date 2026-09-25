import '../core/ids.dart';
import '../data/local/local_store.dart';
import '../models/audit.dart';
import '../models/batch.dart';
import '../models/product.dart';
import '../models/purchase.dart';

/// One invoice line captured by the purchase editor.
class PurchaseDraftLine {
  const PurchaseDraftLine({
    required this.productName,
    this.productId,
    required this.quantity,
    required this.costPricePesewas,
    this.batchNumber,
    this.expiryDate,
  });

  /// Free-text product names get a new catalog product on save.
  final String productName;
  final String? productId;
  final int quantity;
  final int costPricePesewas;
  final String? batchNumber;
  final DateTime? expiryDate;
}

/// Purchase workflow: draft saving and goods receiving.
///
/// Receiving an invoice ("Save & Receive") upserts batches (stock lots)
/// per line and records purchase-receipt stock movements, so Products and
/// Inventory reflect live stock immediately. Everything is persisted
/// locally first; the optional [enqueue] hook mirrors records to the cloud
/// when online.
class PurchaseService {
  PurchaseService({
    required LocalStore store,
    Future<void> Function(
            String entityType, String entityId, Map<String, dynamic> payload)?
        enqueue,
    Future<void> Function(AuditLog log)? logAudit,
  })  : _store = store,
        _enqueue = enqueue,
        _logAudit = logAudit;

  final LocalStore _store;
  final Future<void> Function(
      String entityType, String entityId, Map<String, dynamic> payload)? _enqueue;
  final Future<void> Function(AuditLog log)? _logAudit;

  /// Next purchase number for the current local day.
  Future<String> nextPurchaseNumber({DateTime? day}) async {
    final today = day ?? DateTime.now();
    final purchases = await _store.getPurchases();
    final last = PurchaseNumberGenerator.lastSequenceFor(
        today, purchases.map((p) => p.purchaseNumber));
    return PurchaseNumberGenerator(deviceId: _store.deviceId).next(today, last);
  }

  /// Saves (creates or updates) the invoice as a draft. No stock movement.
  Future<Purchase> saveDraft({
    String? purchaseId,
    required String purchaseNumber,
    String? supplierId,
    String? notes,
    DateTime? date,
    required List<PurchaseDraftLine> lines,
  }) async {
    final existing =
        purchaseId == null ? null : await _store.getPurchaseById(purchaseId);
    final purchase = await _build(
      id: purchaseId ?? Ids.purchaseId(),
      operationId: existing?.operationId ?? Ids.operationId(),
      purchaseNumber: purchaseNumber,
      supplierId: supplierId,
      notes: notes,
      createdAt: existing?.createdAt ?? date ?? DateTime.now().toUtc(),
      status: PurchaseStatus.draft,
      lines: lines,
    );
    await _store.putPurchase(purchase);
    await _audit(AuditLog.purchaseCreated, 'purchase', purchase.id,
        after: purchase.toJson());
    await _enqueuePurchase(purchase);
    return purchase;
  }

  /// Saves the invoice as received AND receives the goods into inventory:
  /// one batch per line plus a purchase-receipt stock movement each.
  Future<Purchase> receive({
    String? purchaseId,
    required String purchaseNumber,
    required String supplierId,
    String? notes,
    DateTime? date,
    required List<PurchaseDraftLine> lines,
  }) async {
    final existing =
        purchaseId == null ? null : await _store.getPurchaseById(purchaseId);
    final now = DateTime.now().toUtc();
    final purchase = await _build(
      id: purchaseId ?? Ids.purchaseId(),
      operationId: existing?.operationId ?? Ids.operationId(),
      purchaseNumber: purchaseNumber,
      supplierId: supplierId,
      notes: notes,
      createdAt: existing?.createdAt ?? date ?? now,
      status: PurchaseStatus.received,
      receivedAt: now,
      lines: lines,
    );
    await _store.putPurchase(purchase);
    await _audit(AuditLog.purchaseCreated, 'purchase', purchase.id,
        after: purchase.toJson());

    for (final line in lines) {
      final productId = await _resolveProductId(line);
      await _refreshProductCost(productId, line.costPricePesewas);
      final batch = await _upsertBatch(
          purchase: purchase, productId: productId, line: line, now: now);
      final movement = StockMovement(
        id: Ids.movementId(),
        operationId: Ids.operationId(),
        productId: productId,
        batchId: batch.id,
        quantity: line.quantity,
        movementType: MovementType.purchaseReceipt,
        referenceId: purchase.id,
        reason: 'GRN ${purchase.purchaseNumber}',
        createdAt: now,
      );
      await _store.putMovement(movement);
      await _enqueueEntity(EntityTypes.stockMovement, movement.id, movement.toJson());
      await _audit(
        AuditLog.stockReceived,
        'purchase',
        purchase.id,
        after: {'productId': productId, 'quantity': line.quantity},
      );
    }

    await _enqueuePurchase(purchase);
    return purchase;
  }

  Future<Purchase> _build({
    required String id,
    required String operationId,
    required String purchaseNumber,
    String? supplierId,
    String? notes,
    required DateTime? createdAt,
    required PurchaseStatus status,
    required List<PurchaseDraftLine> lines,
    DateTime? receivedAt,
  }) async {
    var total = 0;
    final items = <PurchaseItem>[];
    for (final line in lines) {
      final productId = await _resolveProductId(line);
      total += line.quantity * line.costPricePesewas;
      items.add(PurchaseItem(
        id: Ids.purchaseItemId(),
        purchaseId: id,
        productId: productId,
        quantity: line.quantity,
        costPricePesewas: line.costPricePesewas,
        batchNumber: _emptyToNull(line.batchNumber),
        expiryDate: line.expiryDate,
      ));
    }
    return Purchase(
      id: id,
      operationId: operationId,
      supplierId: supplierId,
      purchaseNumber: purchaseNumber,
      status: status,
      totalCostPesewas: total,
      receivedAt: receivedAt,
      notes: notes,
      createdAt: createdAt,
      items: items,
    );
  }

  /// Resolves the line to a product id, creating the product when the user
  /// typed a brand-new name.
  Future<String> _resolveProductId(PurchaseDraftLine line) async {
    if (line.productId != null && line.productId!.isNotEmpty) {
      return line.productId!;
    }
    final now = DateTime.now().toUtc();
    final product = Product(
      id: Ids.productId(),
      name: line.productName.trim(),
      sellingPricePesewas: line.costPricePesewas,
      costPricePesewas: line.costPricePesewas,
      createdAt: now,
    );
    await _store.putProduct(product);
    await _audit(AuditLog.productCreated, 'product', product.id,
        after: product.toJson());
    await _enqueueEntity(EntityTypes.product, product.id, product.toJson());
    return product.id;
  }

  /// Keeps the product's cost price fresh from the latest receipt.
  Future<void> _refreshProductCost(String productId, int costPricePesewas) async {
    final product = await _store.getProductById(productId);
    if (product == null) return;
    if (product.costPricePesewas == costPricePesewas) return;
    final updated = product.copyWith(
      costPricePesewas: costPricePesewas,
      sellingPricePesewas: product.sellingPricePesewas > 0
          ? product.sellingPricePesewas
          : costPricePesewas,
    );
    await _store.putProduct(updated);
    await _audit(AuditLog.productUpdated, 'product', product.id,
        before: product.toJson(), after: updated.toJson());
  }

  /// Reuses an open batch matching product + batch# + expiry; otherwise
  /// creates a new lot. Quantities accumulate on the same lot.
  Future<Batch> _upsertBatch({
    required Purchase purchase,
    required String productId,
    required PurchaseDraftLine line,
    required DateTime now,
  }) async {
    final batches = await _store.getBatches(productId: productId);
    for (final batch in batches) {
      final numberMatches = (batch.batchNumber ?? '') == (line.batchNumber ?? '');
      final expiryMatches = _sameDay(batch.expiryDate, line.expiryDate);
      if (numberMatches && expiryMatches && batch.quantity > 0) {
        final updated = batch.copyWith(
          quantity: batch.quantity + line.quantity,
          costPricePesewas: line.costPricePesewas,
          updatedAt: now,
        );
        await _store.putBatch(updated);
        return updated;
      }
    }
    final created = Batch(
      id: Ids.batchId(),
      productId: productId,
      batchNumber: _emptyToNull(line.batchNumber),
      expiryDate: line.expiryDate,
      quantity: line.quantity,
      costPricePesewas: line.costPricePesewas,
      supplierId: purchase.supplierId,
      receivedAt: now,
      createdAt: now,
    );
    await _store.putBatch(created);
    await _audit(AuditLog.batchCreated, 'batch', created.id,
        after: created.toJson());
    return created;
  }

  Future<void> _enqueuePurchase(Purchase purchase) =>
      _enqueueEntity(EntityTypes.purchase, purchase.id, purchase.toJson());

  Future<void> _enqueueEntity(
      String entityType, String entityId, Map<String, dynamic> payload) {
    final enqueue = _enqueue;
    if (enqueue == null) return Future.value();
    return enqueue(entityType, entityId, payload);
  }

  Future<void> _audit(
    String action,
    String entity,
    String entityId, {
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  }) {
    final log = _logAudit;
    if (log == null) return Future.value();
    return log(AuditLog(
      id: '',
      action: action,
      entity: entity,
      entityId: entityId,
      before: before,
      after: after,
    ));
  }

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}