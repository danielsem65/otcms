import 'batch.dart';

/// A queued sync operation (outbox entry).
class SyncOperation {
  const SyncOperation({
    required this.operationId,
    required this.deviceId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.createdAt,
    this.status = SyncStatus.pending,
    this.retryCount = 0,
    this.lastError,
    this.payload = const {},
  });

  final String operationId;
  final String deviceId;

  /// SALE | STOCK_MOVEMENT | PURCHASE | PRODUCT | CATEGORY | SUPPLIER |
  /// PROFILE | NOTIFICATION | AUDIT | STOCK_COUNT
  final String entityType;
  final String entityId;

  /// CREATE | UPDATE | DELETE
  final String operationType;
  final DateTime createdAt;
  final SyncStatus status;
  final int retryCount;
  final String? lastError;
  final Map<String, dynamic> payload;

  SyncOperation copyWith({
    SyncStatus? status,
    int? retryCount,
    String? lastError,
  }) =>
      SyncOperation(
        operationId: operationId,
        deviceId: deviceId,
        entityType: entityType,
        entityId: entityId,
        operationType: operationType,
        createdAt: createdAt,
        status: status ?? this.status,
        retryCount: retryCount ?? this.retryCount,
        lastError: lastError ?? this.lastError,
        payload: payload,
      );

  factory SyncOperation.fromJson(Map<String, dynamic> json) => SyncOperation(
        operationId: json['operationId'] as String,
        deviceId: json['deviceId'] as String? ?? '',
        entityType: json['entityType'] as String,
        entityId: json['entityId'] as String,
        operationType: json['operationType'] as String? ?? 'CREATE',
        createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
        status: SyncStatus.fromDb(json['status'] as String? ?? 'PENDING'),
        retryCount: (json['retryCount'] as int?) ?? 0,
        lastError: json['lastError'] as String?,
        payload: (json['payload'] as Map<String, dynamic>? ?? {}).cast<String, dynamic>(),
      );

  Map<String, dynamic> toJson() => {
        'operationId': operationId,
        'deviceId': deviceId,
        'entityType': entityType,
        'entityId': entityId,
        'operationType': operationType,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'status': status.dbValue,
        'retryCount': retryCount,
        'lastError': lastError,
        'payload': payload,
      };
}

/// Sync bookkeeping: last successful sync points for this device.
class SyncState {
  const SyncState({
    required this.deviceId,
    this.organizationId,
    this.lastPushedAt,
    this.lastPulledAt,
    this.updatedAt,
  });

  final String deviceId;
  final String? organizationId;
  final DateTime? lastPushedAt;
  final DateTime? lastPulledAt;
  final DateTime? updatedAt;

  SyncState copyWith({
    DateTime? lastPushedAt,
    DateTime? lastPulledAt,
    DateTime? updatedAt,
  }) =>
      SyncState(
        deviceId: deviceId,
        organizationId: organizationId,
        lastPushedAt: lastPushedAt ?? this.lastPushedAt,
        lastPulledAt: lastPulledAt ?? this.lastPulledAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
      );

  factory SyncState.fromJson(Map<String, dynamic> json) => SyncState(
        deviceId: json['deviceId'] as String,
        organizationId: json['organizationId'] as String?,
        lastPushedAt: _parseUtc(json['lastPushedAt']),
        lastPulledAt: _parseUtc(json['lastPulledAt']),
        updatedAt: _parseUtc(json['updatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'organizationId': organizationId,
        'lastPushedAt': lastPushedAt?.toUtc().toIso8601String(),
        'lastPulledAt': lastPulledAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}

/// A recorded business conflict awaiting review.
class SyncConflict {
  const SyncConflict({
    required this.id,
    this.organizationId,
    this.operationId,
    this.entityType,
    this.entityId,
    required this.reason,
    this.payload,
    this.status = ConflictStatus.open,
    this.createdAt,
    this.resolvedAt,
  });

  final String id;
  final String? organizationId;
  final String? operationId;
  final String? entityType;
  final String? entityId;
  final String reason;
  final Map<String, dynamic>? payload;
  final ConflictStatus status;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  factory SyncConflict.fromJson(Map<String, dynamic> json) => SyncConflict(
        id: json['id'] as String,
        organizationId: json['organizationId'] as String?,
        operationId: json['operationId'] as String?,
        entityType: json['entityType'] as String?,
        entityId: json['entityId'] as String?,
        reason: json['reason'] as String? ?? '',
        payload: (json['payload'] as Map<String, dynamic>?)?.cast<String, dynamic>(),
        status: ConflictStatus.fromDb(json['status'] as String? ?? 'OPEN'),
        createdAt: _parseUtc(json['createdAt']),
        resolvedAt: _parseUtc(json['resolvedAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organizationId': organizationId,
        'operationId': operationId,
        'entityType': entityType,
        'entityId': entityId,
        'reason': reason,
        'payload': payload,
        'status': status.dbValue,
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'resolvedAt': resolvedAt?.toUtc().toIso8601String(),
      };

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}

enum ConflictStatus {
  open('OPEN'),
  acknowledged('ACKNOWLEDGED'),
  resolved('RESOLVED');

  const ConflictStatus(this.dbValue);
  final String dbValue;

  static ConflictStatus fromDb(String value) => ConflictStatus.values
      .firstWhere((e) => e.dbValue == value, orElse: () => ConflictStatus.open);
}
