import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/data/local/json/json_store.dart';
import 'package:otcms/models/batch.dart';
import 'package:otcms/models/product.dart';
import 'package:otcms/models/sale.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('otcms_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<JsonLocalStore> openStore() async {
    final store = JsonLocalStore(dataDirectory: tempDir.path);
    await store.open();
    return store;
  }

  group('JsonLocalStore', () {
    test('persists products across open/close (JSON read + write)', () async {
      final store = await openStore();
      await store.putProduct(Product(
        id: 'prod_001',
        name: '3FER SYRUP',
        responsible: 'Administrator',
        sellingPricePesewas: 1454,
      ));
      await store.close();

      final reopened = await openStore();
      final products = await reopened.getProducts();
      expect(products.length, 1);
      expect(products.first.name, '3FER SYRUP');
      expect(products.first.sellingPricePesewas, 1454);
      await reopened.close();
    });

    test('products.json exists with structured schema', () async {
      final store = await openStore();
      await store.putProduct(Product(
        id: 'prod_001',
        name: 'X',
        sellingPricePesewas: 100,
      ));
      await store.close();
      final raw = jsonDecode(
          File('${tempDir.path}/data/products.json').readAsStringSync());
      expect((raw as Map<String, dynamic>)['schemaVersion'], 1);
      expect(raw['items'], isA<List>());
      expect((raw['items'] as List).length, 1);
    });

    test('corrupt file recovers without crashing', () async {
      final store = await openStore();
      await store.close();
      final file = File('${tempDir.path}/data/products.json');
      file.writeAsStringSync('{not valid json!!');
      final reopened = await openStore();
      expect(await reopened.getProducts(), isEmpty);
      await reopened.close();
    });

    test('exportAll / importAll round trip', () async {
      final store = await openStore();
      await store.putProduct(Product(
        id: 'prod_001',
        name: 'Paracetamol',
        sellingPricePesewas: 1000,
      ));
      await store.putBatch(Batch(
        id: 'batch_001',
        productId: 'prod_001',
        quantity: 50,
      ));
      await store.putSale(Sale(
        id: 'sale_001',
        operationId: 'op_001',
        invoiceNumber: 'INV-20260817-AB12-0001',
        totalAmountPesewas: 500,
        createdAt: DateTime.utc(2026, 8, 17),
      ));
      final snapshot = await store.exportAll();
      await store.close();

      final fresh = await openStore();
      await fresh.importAll(snapshot);
      expect((await fresh.getProducts()).length, 1);
      expect((await fresh.getBatches()).length, 1);
      expect((await fresh.getSales()).length, 1);
      await fresh.close();
    });

    test('search works by name, barcode and sku', () async {
      final store = await openStore();
      await store.putProducts([
        Product(id: 'p1', name: 'Paracetamol 500mg', sellingPricePesewas: 1000, barcode: '1234'),
        Product(id: 'p2', name: 'ORS', sellingPricePesewas: 500, sku: 'ORS-01'),
        Product(id: 'p3', name: 'Vitamin C', sellingPricePesewas: 1500),
      ]);
      expect((await store.getProducts(search: 'PARA')).length, 1);
      expect((await store.getProducts(search: '1234')).length, 1);
      expect((await store.getProducts(search: 'ors-01')).length, 1);
      expect((await store.getProducts(search: 'c')).length, 1);
      await store.close();
    });

    test('device id is stable across restarts', () async {
      final store = await openStore();
      final id = store.deviceId;
      await store.close();
      final reopened = await openStore();
      expect(reopened.deviceId, id);
      await reopened.close();
    });

    test('daily sales filter by local day', () async {
      final store = await openStore();
      await store.putSale(Sale(
        id: 's1',
        operationId: 'op1',
        invoiceNumber: 'INV-20260817-AB12-0001',
        saleDate: DateTime(2026, 8, 17, 10),
        totalAmountPesewas: 1000,
        createdAt: DateTime.utc(2026, 8, 17, 10),
      ));
      await store.putSale(Sale(
        id: 's2',
        operationId: 'op2',
        invoiceNumber: 'INV-20260816-AB12-0001',
        saleDate: DateTime(2026, 8, 16, 10),
        totalAmountPesewas: 500,
        createdAt: DateTime.utc(2026, 8, 16, 10),
      ));
      final today = await store.getDailySales(DateTime(2026, 8, 17));
      expect(today.length, 1);
      expect(today.first.totalAmountPesewas, 1000);
      await store.close();
    });
  });
}