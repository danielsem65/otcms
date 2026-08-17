import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/data/local/json/json_store.dart';
import 'package:otcms/models/sale.dart';
import 'package:otcms/services/daily_sales_service.dart';

void main() {
  late Directory tempDir;
  late JsonLocalStore store;
  late DailySalesService service;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('otcms_daily_test_');
    store = JsonLocalStore(dataDirectory: tempDir.path);
    await store.open();
    service = DailySalesService(store: store);
  });

  tearDown(() async {
    await store.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> addSale(String id, int totalPesewas, DateTime date, {int utcDay = 15}) async {
    await store.putSale(Sale(
      id: id,
      operationId: 'op_$id',
      invoiceNumber: 'INV-$id',
      saleDate: date,
      saleTime: DateTime(date.year, date.month, date.day, 10, 30),
      createdAt: DateTime.utc(2026, 8, utcDay, 12),
      totalAmountPesewas: totalPesewas,
      items: const [],
    ));
  }

  group('DailySalesService', () {
    test('computes totals in whole pesewas', () async {
      await addSale('s1', 3380, DateTime(2026, 8, 17), utcDay: 17);
      await addSale('s2', 1454, DateTime(2026, 8, 17), utcDay: 17);

      final summary = await service.summaryFor(DateTime(2026, 8, 17));
      expect(summary.transactions, 2);
      expect(summary.totalPesewas, 4834);
      expect(summary.totalPesewas % 100, 34);
      expect(summary.unitsSold, 0);
      expect(summary.averageTransactionPesewas, 2417);
    });

    test('no sales produces zero totals', () async {
      final summary = await service.summaryFor(DateTime(2026, 8, 17));
      expect(summary.transactions, 0);
      expect(summary.totalPesewas, 0);
      expect(summary.unitsSold, 0);
      expect(summary.averageTransactionPesewas, 0);
    });

    test('filters strictly by local day', () async {
      await addSale('yesterday', 500, DateTime(2026, 8, 16), utcDay: 16);
      await addSale('today', 1000, DateTime(2026, 8, 17), utcDay: 17);
      await addSale('tomorrow', 2000, DateTime(2026, 8, 18), utcDay: 18);

      final today = await service.summaryFor(DateTime(2026, 8, 17));
      expect(today.transactions, 1);
      expect(today.totalPesewas, 1000);
    });

    test('salesBetween is inclusive on both ends', () async {
      await addSale('d1', 100, DateTime(2026, 8, 15), utcDay: 15);
      await addSale('d2', 200, DateTime(2026, 8, 17), utcDay: 17);
      await addSale('d3', 300, DateTime(2026, 8, 20), utcDay: 20);

      final sales = await service.salesBetween(DateTime(2026, 8, 16), DateTime(2026, 8, 19));
      expect(sales.length, 1);
      expect(sales.single.id, 'd2');
    });
  });
}