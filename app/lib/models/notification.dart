enum NotificationType {
  expiry('EXPIRY'),
  lowStock('LOW_STOCK'),
  outOfStock('OUT_OF_STOCK'),
  restock('RESTOCK'),
  sync('SYNC'),
  system('SYSTEM');

  const NotificationType(this.dbValue);
  final String dbValue;

  static NotificationType fromDb(String value) => NotificationType.values
      .firstWhere((e) => e.dbValue == value, orElse: () => NotificationType.system);
}

enum NotificationSeverity {
  info('INFO'),
  warning('WARNING'),
  critical('CRITICAL');

  const NotificationSeverity(this.dbValue);
  final String dbValue;

  static NotificationSeverity fromDb(String value) => NotificationSeverity.values
      .firstWhere((e) => e.dbValue == value, orElse: () => NotificationSeverity.info);
}

/// App-level notification (in-app + mirrored to cloud). Local alerts on
/// Android additionally map to system notifications (see notification service).
class AppNotification {
  const AppNotification({
    required this.id,
    this.organizationId,
    this.branchId,
    required this.type,
    this.severity = NotificationSeverity.info,
    required this.title,
    this.body,
    this.data,
    this.read = false,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        organizationId: json['organizationId'] as String?,
        branchId: json['branchId'] as String?,
        type: NotificationType.fromDb(json['type'] as String),
        severity: NotificationSeverity.fromDb(json['severity'] as String? ?? 'INFO'),
        title: json['title'] as String,
        body: json['body'] as String?,
        data: (json['data'] as Map<String, dynamic>?)?.cast<String, dynamic>(),
        read: (json['read'] as bool?) ?? false,
        createdAt: _parseUtc(json['createdAt']),
      );

  final String id;
  final String? organizationId;
  final String? branchId;
  final NotificationType type;
  final NotificationSeverity severity;
  final String title;
  final String? body;

  /// Structured payload, e.g. {productId, batchId, expiryDate, daysLeft}.
  final Map<String, dynamic>? data;

  final bool read;
  final DateTime? createdAt;

  /// Dedup key so the same alert is not re-created on every recompute.
  String get dedupKey {
    final productId = data?['productId'];
    final batchId = data?['batchId'];
    final period = data?['period'];
    return '${type.dbValue}|${productId ?? ''}|${batchId ?? ''}|${period ?? ''}';
  }

  AppNotification asRead() => AppNotification(
        id: id,
        organizationId: organizationId,
        branchId: branchId,
        type: type,
        severity: severity,
        title: title,
        body: body,
        data: data,
        read: true,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organizationId': organizationId,
        'branchId': branchId,
        'type': type.dbValue,
        'severity': severity.dbValue,
        'title': title,
        'body': body,
        'data': data,
        'read': read,
        'createdAt': createdAt?.toUtc().toIso8601String(),
      };

  static DateTime? _parseUtc(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}
