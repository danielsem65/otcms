import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/data/local/json/json_store.dart';
import 'package:otcms/models/audit.dart';
import 'package:otcms/models/batch.dart';
import 'package:otcms/models/product.dart';
import 'package:otcms/models/purchase.dart';
import 'package:otcms/models/supplier.dart';
import 'package:otcms/services/purchase_service.dart';
import 'package:otcms/state/providers.dart';
import 'package:otcms/ui/screens/purchase_editor_screen.dart';
import 'package:otcms/ui/theme.dart';

Future<void> _warm(JsonLocalStore store) async {
  await store.getProducts();
  await store.getCategories();
  await store.getPurchases();
  await store.getSuppliers();
  await store.getAuditLogs();
  await store.getBatches();
  await store.getMovements();
}

void main() {
  late Directory tempDir;
  late JsonLocalStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('otcms_test_editor_');
    store = JsonLocalStore(dataDirectory: tempDir.path);
    await store.open();
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ProviderScope scope(List<Override> overrides, Widget home) => ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          purchaseServiceProvider.overrideWithValue(PurchaseService(
            store: store,
            logAudit: (entry) => store.logAudit(entry),
          )),
          ...overrides,
        ],
        child: MaterialApp(theme: OtcmsTheme.light(), home: home),
      );

  Widget pushEditor() => Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PurchaseEditorScreen(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

  testWidgets('create invoice from catalog suggestions and receive stock',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await store.putProduct(const Product(
        id: 'prod_1',
        name: 'Paracetamol 500mg',
        genericName: 'Paracetamol',
        sellingPricePesewas: 1200,
        costPricePesewas: 800,
      ));
      await store.putProduct(const Product(
        id: 'prod_2',
        name: 'ORS',
        sellingPricePesewas: 500,
      ));
      await store.putSupplier(
          const Supplier(id: 'sup_1', name: 'PharmaLink Ltd'));
      await _warm(store);
    });

    await tester.pumpWidget(scope([], pushEditor()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('New Invoice'), findsOneWidget);

    // Invoice number is auto-generated.
    final invoiceNo = tester
        .widget<TextFormField>(find.byKey(const ValueKey('invoiceNo')))
        .controller!
        .text;
    expect(invoiceNo, startsWith('PUR-'));

    // Type in the product field → suggestions dropdown appears.
    await tester.enterText(
        find.byKey(const ValueKey('productSearchField')), 'Para');
    await tester.pump();
    expect(find.text('Paracetamol 500mg'), findsOneWidget);

    // Pick the suggested product.
    await tester.tap(find.text('Paracetamol 500mg'));
    await tester.pumpAndSettle();

    // Fill the line details and add it.
    await tester.enterText(find.byKey(const ValueKey('addQty')), '25');
    await tester.enterText(find.byKey(const ValueKey('addCost')), '5.00');
    await tester.enterText(find.byKey(const ValueKey('addBatch')), 'B-100');
    await tester.tap(find.byKey(const ValueKey('addItemButton')));
    await tester.pumpAndSettle();

    // The line now totals 25 × ₵5.00 = ₵125.00 (row amount + grand total).
    expect(find.text('₵125.00'), findsNWidgets(2));

    // Select a supplier then receive.
    await tester.tap(find.byKey(const ValueKey('supplierField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PharmaLink Ltd').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('receiveButton')));
    await tester.pumpAndSettle();

    // Persisted purchase, batch and movement.
    final purchases = await tester.runAsync(() => store.getPurchases());
    expect(purchases, hasLength(1));
    final purchase = purchases!.single;
    expect(purchase.status, PurchaseStatus.received);
    expect(purchase.totalCostPesewas, 12500); // 25 × ₵5.00
    expect(purchase.items, hasLength(1));
    expect(purchase.items.single.batchNumber, 'B-100');
    expect(purchase.supplierId, 'sup_1');

    final batches = await tester.runAsync(() => store.getBatches(productId: 'prod_1'));
    expect(batches, hasLength(1));
    expect(batches!.single.quantity, 25);

    final movements =
        await tester.runAsync(() => store.getMovements(productId: 'prod_1'));
    expect(movements, hasLength(1));
    expect(movements!.single.movementType, MovementType.purchaseReceipt);
    expect(movements.single.quantity, 25);

    final audits = await tester.runAsync(() => store.getAuditLogs());
    expect(audits!.map((a) => a.action), contains(AuditLog.stockReceived));

    // Let debounced writes and snackbars settle before tear-down.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('save as draft does not create stock', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await store.putProduct(const Product(
        id: 'prod_1',
        name: 'Paracetamol 500mg',
        sellingPricePesewas: 1200,
      ));
      await _warm(store);
    });

    await tester.pumpWidget(scope([], pushEditor()));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('productSearchField')), 'Para');
    await tester.pump();
    await tester.tap(find.text('Paracetamol 500mg'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('addQty')), '10');
    await tester.enterText(find.byKey(const ValueKey('addCost')), '2.00');
    await tester.tap(find.byKey(const ValueKey('addItemButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('saveDraftButton')));
    await tester.pumpAndSettle();

    final purchases = await tester.runAsync(() => store.getPurchases());
    expect(purchases, hasLength(1));
    expect(purchases!.single.status, PurchaseStatus.draft);

    final batches = await tester.runAsync(() => store.getBatches());
    expect(batches, isEmpty);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}