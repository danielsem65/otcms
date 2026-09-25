import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/data/local/json/json_store.dart';
import 'package:otcms/models/purchase.dart';
import 'package:otcms/models/supplier.dart';
import 'package:otcms/services/purchase_service.dart';
import 'package:otcms/state/providers.dart';
import 'package:otcms/ui/screens/purchases_screen.dart';
import 'package:otcms/ui/theme.dart';

Future<void> _warm(JsonLocalStore store) async {
  await store.getProducts();
  await store.getPurchases();
  await store.getSuppliers();
  await store.getBatches();
  await store.getMovements();
}

void main() {
  late Directory tempDir;
  late JsonLocalStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('otcms_test_purchases_');
    store = JsonLocalStore(dataDirectory: tempDir.path);
    await store.open();
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('lists invoices, filters by search and status', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await store.putSupplier(
          const Supplier(id: 'sup_1', name: 'PharmaLink Ltd'));
      await store.putPurchase(Purchase(
        id: 'pur_1',
        operationId: 'op_1',
        supplierId: 'sup_1',
        purchaseNumber: 'PUR-20260925-0001',
        status: PurchaseStatus.received,
        totalCostPesewas: 2500,
        items: const [
          PurchaseItem(
              id: 'poi_1',
              purchaseId: 'pur_1',
              productId: 'p1',
              quantity: 5,
              costPricePesewas: 500),
        ],
        createdAt: DateTime.utc(2026, 9, 25, 10),
      ));
      await store.putPurchase(Purchase(
        id: 'pur_2',
        operationId: 'op_2',
        purchaseNumber: 'PUR-20260925-0002',
        status: PurchaseStatus.draft,
        totalCostPesewas: 0,
        items: const [],
        createdAt: DateTime.utc(2026, 9, 25, 11),
      ));
      await _warm(store);
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        purchaseServiceProvider.overrideWithValue(PurchaseService(store: store)),
      ],
      child: MaterialApp(theme: OtcmsTheme.light(), home: const PurchasesScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('PUR-20260925-0001'), findsOneWidget);
    expect(find.text('PUR-20260925-0002'), findsOneWidget);
    expect(find.text('RECEIVED'), findsOneWidget);
    expect(find.text('DRAFT'), findsOneWidget);

    // Search by supplier name.
    await tester.enterText(find.byType(TextField).first, 'Pharma');
    await tester.pumpAndSettle();
    expect(find.text('PUR-20260925-0001'), findsOneWidget);
    expect(find.text('PUR-20260925-0002'), findsNothing);

    // Clear and filter by status.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('statusFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Received').last);
    await tester.pumpAndSettle();

    expect(find.text('PUR-20260925-0001'), findsOneWidget);
    expect(find.text('PUR-20260925-0002'), findsNothing);

    // Let the search/filter timers settle before tear-down.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('New Invoice opens the editor', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await _warm(store);
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        purchaseServiceProvider.overrideWithValue(PurchaseService(store: store)),
      ],
      child: MaterialApp(theme: OtcmsTheme.light(), home: const PurchasesScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Invoice'));
    await tester.pumpAndSettle();

    expect(find.text('New Invoice'), findsOneWidget); // editor app bar title
    expect(find.text('ITEMS (0)'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Purchases'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}