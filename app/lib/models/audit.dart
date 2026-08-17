/// Audit log entry (mirrored to Supabase when online).
class AuditLog {
  const AuditLog({
    required this.id,
    this.organizationId,
    this.userId,
    this.deviceId,
    required this.action,
    this.entity,
    this.entityId,
    this.before,
    this.after,
    this.createdAt,
  });

  final String id;
  final String? organizationId;
  final String? userId;
  final String? deviceId;
  final String action;
  final String? entity;
  final String? entityId;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final DateTime? createdAt;

  /// Standard action codes.
  static const productCreated = 'PRODUCT_CREATED';
  static const productUpdated = 'PRODUCT_UPDATED';
  static const saleCreated = 'SALE_CREATED';
  static const stockAdjusted = 'STOCK_ADJUSTED';
  static const purchaseCreated = 'PURCHASE_CREATED';
  static const stockReceived = 'STOCK_RECEIVED';
  static const batchCreated = 'BATCH_CREATED';
  static const userLogin = 'USER_LOGIN';
  static const syncStarted = 'SYNC_STARTED';
  static const syncCompleted = 'SYNC_COMPLETED';
  static const syncFailed = 'SYNC_FAILED';
  static const expiryAlert = 'EXPIRY_ALERT';

  factory AuditLog.fromJson(Map<String, dynamic> json) => AuditLog(
        id: json['id'] as String,
        organizationId: json['organizationId'] as String?,
        userId: json['userId'] as String?,
        deviceId: json['deviceId'] as String?,
        action: json['action'] as String,
        entity: json['entity'] as String?,
        entityId: json['entityId'] as String?,
        before: (json['before'] as Map<String, dynamic>?)?.cast<String, dynamic>(),
        after: (json['after'] as Map<String, dynamic>?)?.cast<String, dynamic>(),
        createdAt: _parseUtc(json['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organizationId': organizationId,
        'userId': userId,
        'deviceId': deviceId,
        'action': action,
        'entity': entity,
        'entityId': entityId,
        'before': before,
        'after': after,
        'createdAt': createdAt?.toUtc().toIso8601String(),
      };

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}
