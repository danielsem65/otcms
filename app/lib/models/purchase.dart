import 'batch.dart';

enum PurchaseStatus {
  draft('DRAFT'),
  ordered('ORDERED'),
  received('RECEIVED'),
  cancelled('CANCELLED');

  const PurchaseStatus(this.dbValue);
  final String dbValue;

  static PurchaseStatus fromDb(String value) => PurchaseStatus.values
      .firstWhere((e) => e.dbValue == value, orElse: () => PurchaseStatus.draft);
}

class Purchase {
  const Purchase({
    required this.id,
    required this.operationId,
    this.organizationId,
    this.branchId,
    this.supplierId,
    required this.purchaseNumber,
    this.status = PurchaseStatus.draft,
    this.totalCostPesewas = 0,
    this.receivedAt,
    this.userId,
    this.createdAt,
    this.updatedAt,
    this.items = const [],
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String operationId;
  final String? organizationId;
  final String? branchId;
  final String? supplierId;
  final String purchaseNumber;
  final PurchaseStatus status;
  final int totalCostPesewas;
  final DateTime? receivedAt;
  final String? userId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<PurchaseItem> items;
  final SyncStatus syncStatus;

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
        id: json['id'] as String,
        operationId: json['operationId'] as String,
        organizationId: json['organizationId'] as String?,
        branchId: json['branchId'] as String?,
        supplierId: json['supplierId'] as String?,
        purchaseNumber: json['purchaseNumber'] as String,
        status: PurchaseStatus.fromDb(json['status'] as String? ?? 'DRAFT'),
        totalCostPesewas: (json['totalCostPesewas'] as int?) ?? 0,
        receivedAt: _parseUtc(json['receivedAt']),
        userId: json['userId'] as String?,
        createdAt: _parseUtc(json['createdAt']),
        updatedAt: _parseUtc(json['updatedAt']),
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => PurchaseItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        syncStatus: SyncStatus.fromDb((json['syncStatus'] as String?) ?? 'PENDING'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'operationId': operationId,
        'organizationId': organizationId,
        'branchId': branchId,
        'supplierId': supplierId,
        'purchaseNumber': purchaseNumber,
        'status': status.dbValue,
        'totalCostPesewas': totalCostPesewas,
        'receivedAt': receivedAt?.toUtc().toIso8601String(),
        'userId': userId,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
        'items': items.map((e) => e.toJson()).toList(),
        'syncStatus': syncStatus.dbValue,
      };

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}

class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.purchaseId,
    required this.productId,
    required this.quantity,
    required this.costPricePesewas,
    this.batchNumber,
    this.expiryDate,
    this.manufactureDate,
    this.sellingPricePesewas,
  });

  final String id;
  final String purchaseId;
  final String productId;
  final int quantity;
  final int costPricePesewas;
  final String? batchNumber;
  final DateTime? expiryDate;
  final DateTime? manufactureDate;
  final int? sellingPricePesewas;

  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
        id: json['id'] as String,
        purchaseId: json['purchaseId'] as String,
        productId: json['productId'] as String,
        quantity: json['quantity'] as int,
        costPricePesewas: json['costPricePesewas'] as int,
        batchNumber: json['batchNumber'] as String?,
        expiryDate: _parseDate(json['expiryDate']),
        manufactureDate: _parseDate(json['manufactureDate']),
        sellingPricePesewas: json['sellingPricePesewas'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'purchaseId': purchaseId,
        'productId': productId,
        'quantity': quantity,
        'costPricePesewas': costPricePesewas,
        'batchNumber': batchNumber,
        'expiryDate': _formatDate(expiryDate),
        'manufactureDate': _formatDate(manufactureDate),
        'sellingPricePesewas': sellingPricePesewas,
      };

  static DateTime? _parseDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

  static String? _formatDate(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class StockCountSession {
  const StockCountSession({
    required this.id,
    required this.operationId,
    this.organizationId,
    this.branchId,
    this.status = CountStatus.open,
    this.notes,
    this.userId,
    this.createdAt,
    this.updatedAt,
    this.entries = const [],
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String operationId;
  final String? organizationId;
  final String? branchId;
  final CountStatus status;
  final String? notes;
  final String? userId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<StockCountEntry> entries;
  final SyncStatus syncStatus;

  factory StockCountSession.fromJson(Map<String, dynamic> json) => StockCountSession(
        id: json['id'] as String,
        operationId: json['operationId'] as String,
        organizationId: json['organizationId'] as String?,
        branchId: json['branchId'] as String?,
        status: CountStatus.fromDb(json['status'] as String? ?? 'OPEN'),
        notes: json['notes'] as String?,
        userId: json['userId'] as String?,
        createdAt: _parseUtc(json['createdAt']),
        updatedAt: _parseUtc(json['updatedAt']),
        entries: (json['entries'] as List<dynamic>? ?? [])
            .map((e) => StockCountEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        syncStatus: SyncStatus.fromDb((json['syncStatus'] as String?) ?? 'PENDING'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'operationId': operationId,
        'organizationId': organizationId,
        'branchId': branchId,
        'status': status.dbValue,
        'notes': notes,
        'userId': userId,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
        'entries': entries.map((e) => e.toJson()).toList(),
        'syncStatus': syncStatus.dbValue,
      };

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}

enum CountStatus {
  open('OPEN'),
  posted('POSTED'),
  cancelled('CANCELLED');

  const CountStatus(this.dbValue);
  final String dbValue;

  static CountStatus fromDb(String value) => CountStatus.values
      .firstWhere((e) => e.dbValue == value, orElse: () => CountStatus.open);
}

class StockCountEntry {
  const StockCountEntry({
    required this.id,
    required this.sessionId,
    required this.productId,
    this.batchId,
    required this.systemQty,
    required this.physicalQty,
    this.reason,
  });

  final String id;
  final String sessionId;
  final String productId;
  final String? batchId;
  final int systemQty;
  final int physicalQty;
  final String? reason;

  int get difference => physicalQty - systemQty;

  factory StockCountEntry.fromJson(Map<String, dynamic> json) => StockCountEntry(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        productId: json['productId'] as String,
        batchId: json['batchId'] as String?,
        systemQty: (json['systemQty'] as int?) ?? 0,
        physicalQty: (json['physicalQty'] as int?) ?? 0,
        reason: json['reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'productId': productId,
        'batchId': batchId,
        'systemQty': systemQty,
        'physicalQty': physicalQty,
        'reason': reason,
      };
}
