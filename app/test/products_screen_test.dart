import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/data/local/json/json_store.dart';
import 'package:otcms/models/batch.dart';
import 'package:otcms/models/product.dart';
import 'package:otcms/state/providers.dart';
import 'package:otcms/ui/screens/products_screen.dart';

void main() {
  late Directory tempDir;
  late JsonLocalStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('otcms_test_products_');
    store = JsonLocalStore(dataDirectory: tempDir.path);
    await store.open();
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('Products page acts as inventory with live stock + status',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await store.putProduct(const Product(
        id: 'prod_1',
        name: '3FER SYRUP',
        sellingPricePesewas: 1454,
      ));
      await store.putBatch(const Batch(
        id: 'batch_1',
        productId: 'prod_1',
        quantity: 25,
      ));
      // Warm collection caches before pumping.
      await store.getProducts();
      await store.getBatches();
      await store.getSettings();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const MaterialApp(home: ProductsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('3FER SYRUP'), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
    expect(find.text('HEALTHY'), findsOneWidget);
    expect(find.text('₵14.54'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('out-of-stock product is flagged', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await store.putProduct(const Product(id: 'prod_1', name: 'ORS', sellingPricePesewas: 500));
      await store.getProducts();
      await store.getBatches();
      await store.getSettings();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const MaterialApp(home: ProductsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('OUT OF STOCK'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}