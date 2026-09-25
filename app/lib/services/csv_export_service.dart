import '../models/batch.dart';
import '../models/product.dart';
import '../models/purchase.dart';

/// Small dependency-free CSV writer (files open directly in Excel).
///
/// Values are quoted and embedded quotes doubled, so names containing
/// commas or quotes survive a round-trip.
class CsvExport {
  CsvExport._();

  /// Products catalog export.
  static String productsCsv(List<Product> products) {
    final buffer = StringBuffer()
      ..writeln(_row(const [
        'Name',
        'Generic name',
        'Brand',
        'Category',
        'Barcode',
        'SKU',
        'Cost price',
        'Selling price',
        'Reorder level',
        'Active',
      ]));
    for (final p in products) {
      buffer.writeln(_row([
        p.name,
        p.genericName,
        p.brandName,
        p.categoryId,
        p.barcode,
        p.sku,
        p.costPricePesewas == null ? null : _minor(p.costPricePesewas!),
        _minor(p.sellingPricePesewas),
        '${p.reorderLevel}',
        p.active ? 'TRUE' : 'FALSE',
      ]));
    }
    return buffer.toString();
  }

  /// Purchase invoices export.
  static String purchasesCsv(
    List<Purchase> purchases,
    Map<String, String> supplierNames, {
    required String currencyCode,
  }) {
    final buffer = StringBuffer()
      ..writeln(_row(const [
        'Invoice no',
        'Date',
        'Supplier',
        'Status',
        'Items',
        'Total',
        'Received at',
        'Notes',
      ]));
    for (final p in purchases) {
      buffer.writeln(_row([
        p.purchaseNumber,
        p.createdAt?.toLocal().toIso8601String().split('T').first,
        p.supplierId == null ? null : supplierNames[p.supplierId],
        p.status.dbValue,
        '${p.items.length}',
        '${_minor(p.totalCostPesewas)} $currencyCode',
        p.receivedAt?.toLocal().toIso8601String().split('T').first,
        p.notes,
      ]));
    }
    return buffer.toString();
  }

  /// Stock movements export.
  static String movementsCsv(
    List<StockMovement> movements,
    Map<String, String> productNames,
  ) {
    final buffer = StringBuffer()
      ..writeln(_row(const [
        'Date',
        'Product',
        'Type',
        'Qty',
        'Direction',
        'Batch',
        'Reference',
        'Reason',
      ]));
    for (final m in movements) {
      buffer.writeln(_row([
        m.createdAt?.toLocal().toIso8601String().split('T').first,
        productNames[m.productId],
        m.movementType.dbValue,
        '${m.quantity}',
        m.direction > 0 ? 'IN' : 'OUT',
        m.batchId,
        m.referenceId,
        m.reason,
      ]));
    }
    return buffer.toString();
  }

  static String _minor(int pesewas) => (pesewas / 100).toStringAsFixed(2);

  static String _escape(String? value) {
    final raw = value ?? '';
    return '"${raw.replaceAll('"', '""')}"';
  }

  static String _row(List<String?> cells) =>
      cells.map(_escape).join(',');
}