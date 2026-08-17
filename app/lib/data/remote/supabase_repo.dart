import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/sync.dart';
import 'supabase_bootstrap.dart';

/// Cloud repository — the only place that talks to Supabase.
///
/// All mutations go through SECURITY DEFINER RPCs so that
/// organization/branch/role are derived from the JWT server-side and
/// operation ids are deduplicated (idempotency). The anon key is the
/// only credential used; the service-role key never exists in the app.
class SupabaseRepo {
  SupabaseRepo({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  bool get isConfigured => SupabaseBootstrap.isConfigured;

  SupabaseClient get client {
    if (!SupabaseBootstrap.isInitialized) {
      throw StateError('Supabase is not initialized.');
    }
    return _client ?? Supabase.instance.client;
  }

  bool get hasSession => client.auth.currentSession != null;

  // -------------------------------------------------------------- push RPCs

  Future<Map<String, dynamic>> syncSale(Map<String, dynamic> payload) =>
      _rpc('sync_sale', {'p_payload': payload});

  Future<Map<String, dynamic>> syncMovement(Map<String, dynamic> payload) =>
      _rpc('sync_movement', {'p_payload': payload});

  Future<Map<String, dynamic>> syncPurchaseReceipt(Map<String, dynamic> payload) =>
      _rpc('sync_purchase_receipt', {'p_payload': payload});

  Future<Map<String, dynamic>> syncUpsert(String entity, Map<String, dynamic> payload) =>
      _rpc('sync_upsert', {'p_entity': entity, 'p_payload': payload});

  // -------------------------------------------------------------- pull RPCs

  Future<Map<String, dynamic>> pullAllChanges(DateTime? since) =>
      _rpc('pull_all_changes', {'p_since': since?.toUtc().toIso8601String()});

  Future<Map<String, dynamic>> updateSyncPoint(
    String deviceId,
    DateTime? pushedAt,
    DateTime? pulledAt,
  ) =>
      _rpc('update_sync_point', {
        'p_device_id': deviceId,
        'p_pushed_at': pushedAt?.toUtc().toIso8601String(),
        'p_pulled_at': pulledAt?.toUtc().toIso8601String(),
      });

  Future<Map<String, dynamic>> ackConflict(String conflictId) =>
      _rpc('ack_conflict', {'p_conflict_id': conflictId});

  Future<Map<String, dynamic>> _rpc(String name, Map<String, dynamic> params) async {
    final res = await client.rpc(name, params: params);
    return _asMap(res);
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    }
    return {'status': 'ERROR', 'message': 'unexpected response'};
  }

  /// Parses a sync state reported by the server into a client model.
  static SyncState syncStateFromServer(
    Map<String, dynamic> raw,
    String deviceId, {
    DateTime? localPushedAt,
    DateTime? localPulledAt,
  }) =>
      SyncState(
        deviceId: deviceId,
        organizationId: raw['organizationId'] as String?,
        lastPushedAt: localPushedAt ?? _parse(raw['last_pushed_at']),
        lastPulledAt: localPulledAt ?? _parse(raw['last_pulled_at']),
        updatedAt: DateTime.now().toUtc(),
      );

  static DateTime? _parse(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
}