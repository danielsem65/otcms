import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/data/local/json/json_store.dart';
import 'package:otcms/models/batch.dart';
import 'package:otcms/models/product.dart';
import 'package:otcms/models/purchase.dart';
import 'package:otcms/services/purchase_service.dart';

void main() {
  late Directory tempDir;
  late JsonLocalStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('otcms_test_pur_');
    store = JsonLocalStore(dataDirectory: tempDir.path);
    await store.open();
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  PurchaseDraftLine line({
    String? productId,
    String productName = 'Paracetamol 500mg',
    int quantity = 10,
    int costPricePesewas = 800,
    String? batchNumber,
    DateTime? expiryDate,
  }) =>
      PurchaseDraftLine(
        productId: productId,
        productName: productName,
        quantity: quantity,
        costPricePesewas: costPricePesewas,
        batchNumber: batchNumber,
        expiryDate: expiryDate,
      );

  test('receive creates purchase, batch and movement; stock is live', () async {
    const product = Product(
      id: 'prod_1',
      name: 'Paracetamol 500mg',
      sellingPricePesewas: 1200,
      costPricePesewas: 800,
    );
    await store.putProduct(product);

    final service = PurchaseService(store: store);
    final purchase = await service.receive(
      purchaseNumber: 'PUR-20260925-0001',
      supplierId: 'sup_1',
      lines: [
        line(
          productId: 'prod_1',
          quantity: 10,
          costPricePesewas: 800,
          batchNumber: 'B-100',
          expiryDate: DateTime(2027, 1, 1),
        ),
      ],
    );

    expect(purchase.status, PurchaseStatus.received);
    expect(purchase.totalCostPesewas, 8000);
    expect(purchase.items, hasLength(1));
    expect(purchase.items.single.batchNumber, 'B-100');

    final stored = await store.getPurchaseById(purchase.id);
    expect(stored, isNotNull);
    expect(stored!.status, PurchaseStatus.received);

    final batches = await store.getBatches(productId: 'prod_1');
    expect(batches, hasLength(1));
    expect(batches.single.quantity, 10);
    expect(batches.single.expiryDate, DateTime(2027, 1, 1));

    final movements = await store.getMovements(productId: 'prod_1');
    expect(movements, hasLength(1));
    expect(movements.single.movementType, MovementType.purchaseReceipt);
    expect(movements.single.quantity, 10);
  });

  test('receiving the same batch key twice accumulates quantity', () async {
    await store.putProduct(const Product(
      id: 'prod_1',
      name: 'ORS',
      sellingPricePesewas: 500,
    ));

    final service = PurchaseService(store: store);
    await service.receive(
      purchaseNumber: 'PUR-20260925-0001',
      supplierId: 'sup_1',
      lines: [
        line(productId: 'prod_1', quantity: 5, batchNumber: 'OR-1'),
      ],
    );
    await service.receive(
      purchaseNumber: 'PUR-20260925-0002',
      supplierId: 'sup_1',
      lines: [
        line(productId: 'prod_1', quantity: 7, batchNumber: 'OR-1'),
      ],
    );

    final batches = await store.getBatches(productId: 'prod_1');
    expect(batches, hasLength(1));
    expect(batches.single.quantity, 12);
    final movements = await store.getMovements(productId: 'prod_1');
    expect(movements, hasLength(2));
  });

  test('different batch numbers create separate lots', () async {
    await store.putProduct(const Product(
      id: 'prod_1',
      name: 'ORS',
      sellingPricePesewas: 500,
    ));

    final service = PurchaseService(store: store);
    await service.receive(
      purchaseNumber: 'PUR-20260925-0001',
      supplierId: 'sup_1',
      lines: [
        line(productId: 'prod_1', quantity: 5, batchNumber: 'OR-1'),
        line(productId: 'prod_1', quantity: 3, batchNumber: 'OR-2'),
      ],
    );

    final batches = await store.getBatches(productId: 'prod_1');
    expect(batches, hasLength(2));
    expect(batches.map((b) => b.batchNumber).toSet(), {'OR-1', 'OR-2'});
  });

  test('free-text product name creates a catalog product', () async {
    final service = PurchaseService(store: store);
    await service.receive(
      purchaseNumber: 'PUR-20260925-0001',
      supplierId: 'sup_1',
      lines: [
        line(productName: 'Amoxicillin 250mg', quantity: 20, costPricePesewas: 1500),
      ],
    );

    final products = await store.getProducts();
    expect(products.map((p) => p.name), contains('Amoxicillin 250mg'));
    final created = products.firstWhere((p) => p.name == 'Amoxicillin 250mg');
    expect(created.costPricePesewas, 1500);
    // Default selling price equals cost when the price is unknown.
    expect(created.sellingPricePesewas, 1500);

    final batches = await store.getBatches(productId: created.id);
    expect(batches.single.quantity, 20);
  });

  test('saveDraft persists a draft without touching stock', () async {
    await store.putProduct(const Product(
      id: 'prod_1',
      name: 'ORS',
      sellingPricePesewas: 500,
    ));

    final service = PurchaseService(store: store);
    final draft = await service.saveDraft(
      purchaseNumber: 'PUR-20260925-0009',
      supplierId: null,
      notes: 'Order pending',
      lines: [
        line(productId: 'prod_1', quantity: 5, costPricePesewas: 300),
      ],
    );

    expect(draft.status, PurchaseStatus.draft);
    expect(draft.notes, 'Order pending');
    expect(draft.totalCostPesewas, 1500);

    final batches = await store.getBatches(productId: 'prod_1');
    expect(batches, isEmpty);
    final movements = await store.getMovements();
    expect(movements, isEmpty);
  });

  test('purchase numbers sequence per day', () async {
    final service = PurchaseService(store: store);
    final first = await service.nextPurchaseNumber();
    final second = await service.nextPurchaseNumber();
    expect(first, startsWith('PUR-'));
    expect(second, isNot(first));

    // After persisting a received invoice the next number keeps climbing.
    await service.receive(
      purchaseNumber: first,
      supplierId: 'sup_1',
      lines: [
        line(productName: 'Vitamin C', quantity: 1, costPricePesewas: 100),
      ],
    );
    final third = await service.nextPurchaseNumber();
    expect(third, isNot(second));
  });
}