import 'package:uuid/uuid.dart';

/// ID generation. Every entity gets a typed, globally unique id:
/// `prod_`, `batch_`, `sale_`, `si_` (sale item), `sup_`, `cat_`, `pur_`,
/// `poi_` (purchase item), `mov_` (stock movement), `op_` (sync operation),
/// `notif_`, `aud_`, `scc_` (stock count session), `sce_` (stock count entry).
class Ids {
  static const _uuid = Uuid();

  static String newId(String prefix) {
    final raw = _uuid.v4().replaceAll('-', '');
    return '${prefix}_${raw.substring(0, 24)}';
  }

  static String productId() => newId('prod');
  static String categoryId() => newId('cat');
  static String supplierId() => newId('sup');
  static String batchId() => newId('batch');
  static String saleId() => newId('sale');
  static String saleItemId() => newId('si');
  static String purchaseId() => newId('pur');
  static String purchaseItemId() => newId('poi');
  static String movementId() => newId('mov');
  static String operationId() => newId('op');
  static String notificationId() => newId('notif');
  static String auditId() => newId('aud');
  static String countSessionId() => newId('scc');
  static String countEntryId() => newId('sce');
  static String deviceId() => 'dev_${_uuid.v4().replaceAll('-', '').substring(0, 24)}';
}

/// Invoice numbering — collision-resistant offline.
///
/// Format: `INV-YYYYMMDD-<devicePrefix>-<dailySequence>`
/// e.g. `INV-20260817-1A2F-0042`
///
/// The device prefix (first 4 chars of the device id, uppercased) makes
/// numbers unique across devices even when offline; the daily sequence is
/// tracked per device. Supabase additionally enforces uniqueness.
class InvoiceNumberGenerator {
  InvoiceNumberGenerator({required this.deviceId});

  final String deviceId;

  static final RegExp _pattern = RegExp(r'^INV-\d{8}-[A-Z0-9]{4}-\d{4}$');

  static bool isValid(String invoiceNumber) => _pattern.hasMatch(invoiceNumber);

  /// Generates the next invoice number for [day] (local date) given the
  /// last used sequence for that day. Sequence wraps into 4 digits.
  String next(DateTime day, int lastSequence) {
    final date = '${day.year.toString().padLeft(4, '0')}'
        '${day.month.toString().padLeft(2, '0')}'
        '${day.day.toString().padLeft(2, '0')}';
    final prefix = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final dev = prefix.length >= 4 ? prefix.substring(0, 4) : prefix.padRight(4, 'X');
    final seq = ((lastSequence + 1) % 10000).toString().padLeft(4, '0');
    return 'INV-$date-$dev-$seq';
  }
}
