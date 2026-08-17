import 'dart:convert';

import '../core/ids.dart';
import '../core/money.dart';
import '../core/result.dart';
import '../data/local/local_store.dart';
import '../models/batch.dart';
import '../models/product.dart';
import '../models/sync.dart';
import 'audit_service.dart';

/// Result of importing the pharmacy's legacy product list.
class ProductImportSummary {
  const ProductImportSummary({
    required this.totalRead,
    required this.imported,
    required this.skippedInvalid,
  });

  final int totalRead;
  final int imported;
  final int skippedInvalid;
}

/// Imports the pharmacy's existing product JSON.
///
/// The legacy format is:
///   [ { "Name": "3FER SYRUP", "Responsible": "Administrator", "Sales Price": 14.54 } ]
///
/// Every product name is preserved exactly; prices are converted to
/// integer pesewas (safe Money). Products already present (same name)
/// are updated rather than duplicated. No information is invented.
class ProductImportService {
  ProductImportService({required LocalStore store, required AuditService audit});

  final LocalStore store;
  final AuditService audit;

  /// Imports from raw JSON text (an array of legacy product maps).
  Future<Result<ProductImportSummary>> importJson(String raw) async {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return fail(OtcmsError.validation('Products file must be a JSON array.'));
      }
      return importMaps(decoded.cast<Map<String, dynamic>>());
    } on FormatException {
      return fail(OtcmsError.validation('The file is not valid JSON.'));
    }
  }

  Future<Result<ProductImportSummary>> importMaps(List<Map<String, dynamic>> maps) async {
    var imported = 0;
    var skippedInvalid = 0;
    final now = DateTime.now().toUtc();
    final existing = await store.getProducts();
    final byName = {for (final p in existing) p.name.toUpperCase(): p};

    final toUpsert = <Product>[];

    for (final map in maps) {
      final name = (map['Name'] as String?)?.trim();
      final responsible = (map['Responsible'] as String?)?.trim();
      final price = Money.tryParse(map['Sales Price']?.toString());

      if (name == null || name.isEmpty) {
        skippedInvalid++;
        continue;
      }
      if (price == null) {
        skippedInvalid++;
        continue;
      }

      final existingProduct = byName[name.toUpperCase()];
      if (existingProduct != null) {
        // Preserve the original name; refresh price/responsible if present.
        if (existingProduct.sellingPricePesewas != price.pesewas ||
            (responsible != null && existingProduct.responsible != responsible)) {
          toUpsert.add(existingProduct.copyWith(
            sellingPricePesewas: price.pesewas,
            responsible: responsible ?? existingProduct.responsible,
          ));
        }
      } else {
        toUpsert.add(Product(
          id: Ids.productId(),
          name: name,
          responsible: responsible,
          sellingPricePesewas: price.pesewas,
          reorderLevel: 10,
          minimumStock: 5,
          targetStock: 50,
          reorderQuantity: 20,
          createdAt: now,
          updatedAt: now,
        ));
      }
      imported++;
    }

    if (toUpsert.isNotEmpty) {
      await store.putProducts(toUpsert);
      await audit.log(AuditLog(
        id: Ids.auditId(),
        action: AuditLog.productCreated,
        entity: 'catalog_import',
        after: {'imported': imported},
        createdAt: now,
      ));
    }

    return ok(ProductImportSummary(
      totalRead: maps.length,
      imported: imported,
      skippedInvalid: skippedInvalid,
    ));
  }
}