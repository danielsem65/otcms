import '../core/ids.dart';
import '../core/result.dart';
import '../data/local/local_store.dart';
import '../models/audit.dart';
import '../models/user.dart';

/// Local audit trail (mirrored to Supabase when online).
class AuditService {
  AuditService({required LocalStore store, String? deviceId}) : _store = store, _deviceId = deviceId;

  final LocalStore _store;
  final String? _deviceId;

  Future<void> log(
    AuditLog entry, {
    String? userId,
    String? deviceId,
  }) {
    final enriched = AuditLog(
      id: entry.id.isEmpty ? Ids.auditId() : entry.id,
      organizationId: entry.organizationId,
      userId: userId ?? entry.userId,
      deviceId: deviceId ?? _deviceId ?? entry.deviceId,
      action: entry.action,
      entity: entry.entity,
      entityId: entry.entityId,
      before: entry.before,
      after: entry.after,
      createdAt: entry.createdAt ?? DateTime.now().toUtc(),
    );
    return _store.logAudit(enriched);
  }

  Future<Result<AuditLog>> login(UserProfile user) async {
    final entry = AuditLog(
      id: Ids.auditId(),
      action: AuditLog.userLogin,
      entity: 'user',
      entityId: user.id,
      userId: user.authUserId,
      after: {'displayName': user.displayName, 'role': user.role.dbValue},
      createdAt: DateTime.now().toUtc(),
    );
    await _store.logAudit(entry);
    return ok(entry);
  }

  Future<Result<void>> syncStarted() async {
    await _store.logAudit(AuditLog(
      id: Ids.auditId(),
      action: AuditLog.syncStarted,
      createdAt: DateTime.now().toUtc(),
    ));
    return const Ok(null);
  }

  Future<Result<void>> syncCompleted(int pushed, int pulled) async {
    await _store.logAudit(AuditLog(
      id: Ids.auditId(),
      action: AuditLog.syncCompleted,
      after: {'pushed': pushed, 'pulled': pulled},
      createdAt: DateTime.now().toUtc(),
    ));
    return const Ok(null);
  }
}