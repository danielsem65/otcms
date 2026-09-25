import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/models/batch.dart';
import 'package:otcms/models/product.dart';
import 'package:otcms/models/purchase.dart';
import 'package:otcms/services/csv_export_service.dart';

void main() {
  test('products CSV has header and escaped values', () {
    final csv = CsvExport.productsCsv([
      const Product(
        id: 'p1',
        name: 'Amox "500", 20s',
        barcode: '1234',
        sellingPricePesewas: 1500,
        costPricePesewas: 1000,
        reorderLevel: 12,
      ),
    ]);

    expect(csv, startsWith('"Name","Generic name","Brand","Category"'));
    expect(csv, contains('"Amox ""500"", 20s"'));
    expect(csv, contains('"10.00","15.00"'));
    expect(csv, contains('"12"'));
  });

  test('purchases CSV includes supplier + total', () {
    final csv = CsvExport.purchasesCsv(
      [
        Purchase(
          id: 'pur_1',
          operationId: 'op_1',
          purchaseNumber: 'PUR-20260925-0001',
          status: PurchaseStatus.received,
          totalCostPesewas: 2500,
          supplierId: 'sup_1',
          items: const [PurchaseItem(id: 'poi_1', purchaseId: 'pur_1', productId: 'p1', quantity: 5, costPricePesewas: 500)],
          createdAt: DateTime.utc(2026, 9, 25),
          receivedAt: DateTime.utc(2026, 9, 26),
          notes: 'Paid, 30 days',
        ),
      ],
      {'sup_1': 'PharmaLink Ltd'},
      currencyCode: 'GH₵',
    );

    expect(csv, startsWith('"Invoice no","Date","Supplier","Status"'));
    expect(csv, contains('"PUR-20260925-0001"'));
    expect(csv, contains('"PharmaLink Ltd"'));
    expect(csv, contains('"RECEIVED"'));
    expect(csv, contains('"25.00 GH₵"'));
    expect(csv, contains('"Paid, 30 days"'));
  });

  test('movements CSV shows direction', () {
    final csv = CsvExport.movementsCsv(
      [
        const StockMovement(
          id: 'mov_1',
          operationId: 'op_1',
          productId: 'p1',
          batchId: 'batch_1',
          quantity: 25,
          movementType: MovementType.purchaseReceipt,
          referenceId: 'pur_1',
          reason: 'GRN PUR-1',
        ),
      ],
      {'p1': 'Paracetamol 500mg'},
    );

    expect(csv, startsWith('"Date","Product","Type","Qty"'));
    expect(csv, contains('"Paracetamol 500mg"'));
    expect(csv, contains('"PURCHASE_RECEIPT"'));
    expect(csv, contains('"25"'));
    expect(csv, contains('"IN"'));
  });

  test('commas and quotes inside supplier names survive round trip', () {
    final csv = CsvExport.purchasesCsv(
      [
        const Purchase(
          id: 'pur_1',
          operationId: 'op_1',
          purchaseNumber: 'PUR-1',
          supplierId: 's1',
          items: [],
        ),
      ],
      {'s1': '"Big" Pharma, & Co'},
      currencyCode: 'GH₵',
    );
    expect(csv, contains('"""Big"" Pharma, & Co"'));
  });
}