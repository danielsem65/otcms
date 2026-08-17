import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/data/local/json/json_store.dart';
import 'package:otcms/services/audit_service.dart';
import 'package:otcms/services/product_import_service.dart';

const legacySample = '''
[
  {"Name": "3FER SYRUP", "Responsible": "Administrator", "Sales Price": 33.8},
  {"Name": "PARACETAMOL 500MG", "Responsible": "Nurse Ama", "Sales Price": 14.54},
  {"Name": "ORS", "Responsible": "", "Sales Price": 50.0},
  {"Name": "VITAMIN C", "Responsible": "Doctor Kofi", "Sales Price": "12.00"}
]
''';

void main() {
  late Directory tempDir;
  late JsonLocalStore store;
  late ProductImportService service;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('otcms_import_test_');
    store = JsonLocalStore(dataDirectory: tempDir.path);
    await store.open();
    service = ProductImportService(
      store: store,
      audit: AuditService(store: store),
    );
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('ProductImportService', () {
    test('reads legacy array and imports products', () async {
      final result = await service.importJson(legacySample);
      expect(result.isOk, isTrue);
      final summary = result.value;
      expect(summary.totalRead, 4);
      expect(summary.imported, 4);
      expect(summary.skippedInvalid, 0);
      expect((await store.getProducts()).length, 4);
    });

    test('preserves names exactly and price to the pesewa', () async {
      await service.importJson(legacySample);
      final products = await store.getProducts();
      final byName = {for (final p in products) p.name: p};
      expect(byName['3FER SYRUP']!.sellingPricePesewas, 3380);
      expect(byName['PARACETAMOL 500MG']!.sellingPricePesewas, 1454);
      expect(byName['ORS']!.sellingPricePesewas, 5000);
      expect(byName['VITAMIN C']!.sellingPricePesewas, 1200);
      expect(byName['PARACETAMOL 500MG']!.responsible, 'Nurse Ama');
    });

    test('updates existing products instead of duplicating', () async {
      await service.importJson(legacySample);
      await service.importJson(legacySample);
      expect((await store.getProducts()).length, 4);
    });

    test('invalid price types are skipped as invalid', () async {
      final result = await service.importJson('''
[
  {"Name": "X", "Sales Price": "12.00"},
  {"Name": "Y", "Sales Price": null},
  {"Name": "Z", "Sales Price": -5},
  {"Name": "  ", "Sales Price": 10},
  {"Name": "W", "Sales Price": 20}
]
''');
      final summary = result.value;
      expect(summary.totalRead, 5);
      expect(summary.imported, 2);
      expect(summary.skippedInvalid, 3);
    });

    test('handles malformed json gracefully', () async {
      final result = await service.importJson('{not json');
      expect(result.isErr, isTrue);
      expect(result.error.code, 'validation');
      expect(result.error.message, contains('valid JSON'));
    });

    test('handles non-array json gracefully', () async {
      final result = await service.importJson('{"products": []}');
      expect(result.isErr, isTrue);
      expect(result.error.code, 'validation');
    });

    test('empty list imports nothing', () async {
      final result = await service.importJson('[]');
      expect(result.isOk, isTrue);
      expect(result.value.imported, 0);
    });
  });
}