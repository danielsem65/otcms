import 'batch.dart';

/// A completed sale with its items.
///
/// Money fields are integer pesewas. The seller comes from the
/// authenticated profile; the total is always computed by the system.
class Sale {
  const Sale({
    required this.id,
    required this.operationId,
    required this.invoiceNumber,
    this.userId,
    this.sellerName,
    this.deviceId,
    this.branchId,
    this.organizationId,
    this.saleDate,
    this.saleTime,
    this.createdAt,
    required this.totalAmountPesewas,
    this.items = const [],
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final String operationId;
  final String invoiceNumber;
  final String? userId;
  final String? sellerName;
  final String? deviceId;
  final String? branchId;
  final String? organizationId;
  final DateTime? saleDate;
  final DateTime? saleTime;
  final DateTime? createdAt;
  final int totalAmountPesewas;
  final List<SaleItem> items;
  final SyncStatus syncStatus;

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: json['id'] as String,
        operationId: json['operationId'] as String,
        invoiceNumber: json['invoiceNumber'] as String,
        userId: json['userId'] as String?,
        sellerName: json['sellerName'] as String?,
        deviceId: json['deviceId'] as String?,
        branchId: json['branchId'] as String?,
        organizationId: json['organizationId'] as String?,
        saleDate: _parseUtc(json['saleDate']),
        saleTime: _parseUtc(json['saleTime']),
        createdAt: _parseUtc(json['createdAt']),
        totalAmountPesewas: json['totalAmountPesewas'] as int,
        items: (json['items'] as List<dynamic>? ?? [])
            .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        syncStatus: SyncStatus.fromDb((json['syncStatus'] as String?) ?? 'PENDING'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'operationId': operationId,
        'invoiceNumber': invoiceNumber,
        'userId': userId,
        'sellerName': sellerName,
        'deviceId': deviceId,
        'branchId': branchId,
        'organizationId': organizationId,
        'saleDate': _formatDate(saleDate),
        'saleTime': _formatTime(saleTime),
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'totalAmountPesewas': totalAmountPesewas,
        'items': items.map((e) => e.toJson()).toList(),
        'syncStatus': syncStatus.dbValue,
      };

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();

  static String? _formatDate(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String? _formatTime(DateTime? d) => d == null
      ? null
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
}

class SaleItem {
  const SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    this.batchId,
    required this.medicineName,
    required this.quantity,
    required this.unitPricePesewas,
    required this.amountPesewas,
  });

  final String id;
  final String saleId;
  final String productId;
  final String? batchId;
  final String medicineName;
  final int quantity;
  final int unitPricePesewas;
  final int amountPesewas;

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        id: json['id'] as String,
        saleId: json['saleId'] as String,
        productId: json['productId'] as String,
        batchId: json['batchId'] as String?,
        medicineName: json['medicineName'] as String? ?? '',
        quantity: json['quantity'] as int,
        unitPricePesewas: json['unitPricePesewas'] as int,
        amountPesewas: json['amountPesewas'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'saleId': saleId,
        'productId': productId,
        'batchId': batchId,
        'medicineName': medicineName,
        'quantity': quantity,
        'unitPricePesewas': unitPricePesewas,
        'amountPesewas': amountPesewas,
      };
}
