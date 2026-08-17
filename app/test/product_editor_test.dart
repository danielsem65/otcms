import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/data/local/json/json_store.dart';
import 'package:otcms/models/audit.dart';
import 'package:otcms/state/providers.dart';
import 'package:otcms/ui/screens/products_screen.dart';

void main() {
  testWidgets('add and edit a product with persistence', (tester) async {
    final store = JsonLocalStore(dataDirectory: 'otcms_test_products');
    await tester.runAsync(() async {
      await store.open();
      // Warm collection caches (real file IO) so the widget tree can
      // settle under fake async; otherwise loaders spin forever.
      await store.getProducts();
      await store.getCategories();
      await store.getAuditLogs();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const MaterialApp(home: ProductsScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No products yet. Import the pharmacy product list from Settings.'),
        findsOneWidget);

    // Create a product.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('New product'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('name')), 'Paracetamol 500mg');
    await tester.enterText(find.byKey(const ValueKey('category')), 'Analgesics');
    await tester.enterText(find.byKey(const ValueKey('barcode')), '0123456789');
    await tester.enterText(find.byKey(const ValueKey('sellingPrice')), '12.50');
    await tester.enterText(find.byKey(const ValueKey('costPrice')), '9.00');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Paracetamol 500mg'), findsOneWidget);

    final created = (await tester.runAsync(() => store.getProducts(search: 'para')))!;
    expect(created, hasLength(1));
    expect(created.single.sellingPricePesewas, 1250);
    expect(created.single.costPricePesewas, 900);
    expect(created.single.active, isTrue);

    final categories = (await tester.runAsync(() => store.getCategories()))!;
    expect(categories.map((c) => c.name), contains('Analgesics'));
    expect(created.single.categoryId,
        categories.firstWhere((c) => c.name == 'Analgesics').id);

    final audit = (await tester.runAsync(() => store.getAuditLogs()))!;
    expect(audit.map((e) => e.action), contains(AuditLog.productCreated));

    // Open as edit, verify the form is prefilled, and change the price.
    await tester.tap(find.text('Paracetamol 500mg'));
    await tester.pumpAndSettle();
    expect(find.text('Edit product'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '12.50'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('sellingPrice')), '15.00');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final updated = (await tester.runAsync(() => store.getProducts()))!;
    expect(updated, hasLength(1));
    expect(updated.single.sellingPricePesewas, 1500);

    final audit2 = (await tester.runAsync(() => store.getAuditLogs()))!;
    expect(audit2.map((e) => e.action), contains(AuditLog.productUpdated));

    // Let the success snackbars auto-dismiss before the test ends.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.runAsync(() => store.close());
  });
}