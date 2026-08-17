/// Batch (stock lot) and stock movement models.
///
/// Stock movements are the transactional inventory truth: batch and
/// product quantities are always derived from the sum of movements.
class Batch {
  const Batch({
    required this.id,
    this.organizationId,
    this.branchId,
    required this.productId,
    this.batchNumber,
    this.expiryDate,
    this.manufactureDate,
    required this.quantity,
    this.costPricePesewas,
    this.sellingPricePesewas,
    this.supplierId,
    this.receivedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory Batch.fromJson(Map<String, dynamic> json) => Batch(
        id: json['id'] as String,
        organizationId: json['organizationId'] as String?,
        branchId: json['branchId'] as String?,
        productId: json['productId'] as String,
        batchNumber: json['batchNumber'] as String?,
        expiryDate: _parseDate(json['expiryDate']),
        manufactureDate: _parseDate(json['manufactureDate']),
        quantity: (json['quantity'] as int?) ?? 0,
        costPricePesewas: json['costPricePesewas'] as int?,
        sellingPricePesewas: json['sellingPricePesewas'] as int?,
        supplierId: json['supplierId'] as String?,
        receivedAt: _parseUtc(json['receivedAt']),
        createdAt: _parseUtc(json['createdAt']),
        updatedAt: _parseUtc(json['updatedAt']),
      );

  final String id;
  final String? organizationId;
  final String? branchId;
  final String productId;
  final String? batchNumber;
  final DateTime? expiryDate;
  final DateTime? manufactureDate;

  /// Remaining sellable quantity (derived from movements).
  final int quantity;

  final int? costPricePesewas;
  final int? sellingPricePesewas;
  final String? supplierId;
  final DateTime? receivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasExpiry => expiryDate != null;

  /// True when the batch is strictly past its expiry date.
  bool isExpiredOn(DateTime today) =>
      expiryDate != null && !expiryDate!.isAfter(today);

  /// Days remaining until expiry (negative when expired).
  int daysToExpiryOn(DateTime today) {
    if (expiryDate == null) return 1 << 30;
    final start = DateTime(today.year, today.month, today.day);
    final end = DateTime(expiryDate!.year, expiryDate!.month, expiryDate!.day);
    return end.difference(start).inDays;
  }

  Batch copyWith({int? quantity, int? costPricePesewas, int? sellingPricePesewas, DateTime? updatedAt}) =>
      Batch(
        id: id,
        organizationId: organizationId,
        branchId: branchId,
        productId: productId,
        batchNumber: batchNumber,
        expiryDate: expiryDate,
        manufactureDate: manufactureDate,
        quantity: quantity ?? this.quantity,
        costPricePesewas: costPricePesewas ?? this.costPricePesewas,
        sellingPricePesewas: sellingPricePesewas ?? this.sellingPricePesewas,
        supplierId: supplierId,
        receivedAt: receivedAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organizationId': organizationId,
        'branchId': branchId,
        'productId': productId,
        'batchNumber': batchNumber,
        'expiryDate': _formatDate(expiryDate),
        'manufactureDate': _formatDate(manufactureDate),
        'quantity': quantity,
        'costPricePesewas': costPricePesewas,
        'sellingPricePesewas': sellingPricePesewas,
        'supplierId': supplierId,
        'receivedAt': receivedAt?.toUtc().toIso8601String(),
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final d = DateTime.tryParse(v.toString());
    return d;
  }

  static String? _formatDate(DateTime? d) =>
      d == null ? null : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}

/// Movement types. `SALE`, `PURCHASE_RETURN`, `DAMAGE`, `EXPIRED`,
/// `TRANSFER_OUT` and negative `STOCK_ADJUSTMENT`s decrement stock;
/// everything else increments.
enum MovementType {
  openingBalance('OPENING_BALANCE'),
  purchaseReceipt('PURCHASE_RECEIPT'),
  sale('SALE'),
  saleReturn('SALE_RETURN'),
  purchaseReturn('PURCHASE_RETURN'),
  stockAdjustment('STOCK_ADJUSTMENT'),
  damage('DAMAGE'),
  expired('EXPIRED'),
  transferIn('TRANSFER_IN'),
  transferOut('TRANSFER_OUT');

  const MovementType(this.dbValue);
  final String dbValue;

  static MovementType fromDb(String value) => MovementType.values
      .firstWhere((e) => e.dbValue == value, orElse: () => MovementType.stockAdjustment);

  /// Direction of stock flow: 1 adds stock, -1 removes stock.
  int get direction => switch (this) {
        MovementType.sale ||
        MovementType.purchaseReturn ||
        MovementType.damage ||
        MovementType.expired ||
        MovementType.transferOut => -1,
        _ => 1,
      };

  String get label => switch (this) {
        MovementType.openingBalance => 'Opening Balance',
        MovementType.purchaseReceipt => 'Purchase Receipt',
        MovementType.sale => 'Sale',
        MovementType.saleReturn => 'Sale Return',
        MovementType.purchaseReturn => 'Purchase Return',
        MovementType.stockAdjustment => 'Stock Adjustment',
        MovementType.damage => 'Damage',
        MovementType.expired => 'Expired',
        MovementType.transferIn => 'Transfer In',
        MovementType.transferOut => 'Transfer Out',
      };
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.operationId,
    required this.productId,
    required this.batchId,
    required this.quantity,
    required this.movementType,
    this.referenceId,
    this.reason,
    this.userId,
    this.branchId,
    this.organizationId,
    this.createdAt,
    this.syncStatus = SyncStatus.pending,
  });

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: json['id'] as String,
        operationId: json['operationId'] as String,
        productId: json['productId'] as String,
        batchId: json['batchId'] as String,
        quantity: json['quantity'] as int,
        movementType: MovementType.fromDb(json['movementType'] as String),
        referenceId: json['referenceId'] as String?,
        reason: json['reason'] as String?,
        userId: json['userId'] as String?,
        branchId: json['branchId'] as String?,
        organizationId: json['organizationId'] as String?,
        createdAt: _parseUtc(json['createdAt']),
        syncStatus: SyncStatus.fromDb((json['syncStatus'] as String?) ?? 'PENDING'),
      );

  final String id;
  final String operationId;
  final String productId;
  final String batchId;

  /// Always positive; direction comes from [movementType].
  final int quantity;
  final MovementType movementType;
  final String? referenceId;
  final String? reason;
  final String? userId;
  final String? branchId;
  final String? organizationId;
  final DateTime? createdAt;
  final SyncStatus syncStatus;

  int get direction => movementType.direction;

  Map<String, dynamic> toJson() => {
        'id': id,
        'operationId': operationId,
        'productId': productId,
        'batchId': batchId,
        'quantity': quantity,
        'movementType': movementType.dbValue,
        'referenceId': referenceId,
        'reason': reason,
        'userId': userId,
        'branchId': branchId,
        'organizationId': organizationId,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'syncStatus': syncStatus.dbValue,
      };

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}

/// Sync lifecycle for locally created records.
enum SyncStatus {
  pending('PENDING'),
  syncing('SYNCING'),
  synced('SYNCED'),
  failed('FAILED'),
  conflict('CONFLICT');

  const SyncStatus(this.dbValue);
  final String dbValue;

  static SyncStatus fromDb(String value) =>
      SyncStatus.values.firstWhere((e) => e.dbValue == value, orElse: () => SyncStatus.pending);
}
