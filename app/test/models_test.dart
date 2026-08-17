import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/models/batch.dart';
import 'package:otcms/models/product.dart';
import 'package:otcms/models/sale.dart';

void main() {
  group('Product JSON round trip', () {
    test('minimal legacy-style product stays valid', () {
      final product = const Product(
        id: 'prod_001',
        name: '3FER SYRUP',
        responsible: 'Administrator',
        sellingPricePesewas: 1454,
      );
      final restored = Product.fromJson(product.toJson());
      expect(restored.name, '3FER SYRUP');
      expect(restored.responsible, 'Administrator');
      expect(restored.sellingPricePesewas, 1454);
      expect(restored.active, isTrue);
    });

    test('all optional fields round trip', () {
      final product = Product(
        id: 'prod_x',
        name: 'Paracetamol 500mg',
        genericName: 'Paracetamol',
        brandName: 'Panadol',
        barcode: '1234567890',
        sku: 'PARA-500',
        costPricePesewas: 500,
        sellingPricePesewas: 1000,
        reorderLevel: 30,
        minimumStock: 10,
        targetStock: 120,
        createdAt: DateTime.utc(2026, 8, 17, 10),
      );
      final restored = Product.fromJson(product.toJson());
      expect(restored.genericName, 'Paracetamol');
      expect(restored.barcode, '1234567890');
      expect(restored.reorderLevel, 30);
      expect(restored.createdAt, DateTime.utc(2026, 8, 17, 10));
    });
  });

  group('Batch', () {
    test('expiry calculations', () {
      final today = DateTime(2026, 8, 17);
      final soon = Batch(
        id: 'batch_1',
        productId: 'prod_1',
        expiryDate: DateTime(2026, 8, 27),
        quantity: 100,
      );
      final expired = Batch(
        id: 'batch_2',
        productId: 'prod_1',
        expiryDate: DateTime(2026, 8, 10),
        quantity: 40,
      );
      final none = const Batch(id: 'batch_3', productId: 'prod_1', quantity: 5);

      expect(soon.isExpiredOn(today), isFalse);
      expect(expired.isExpiredOn(today), isTrue);
      expect(none.hasExpiry, isFalse);
      expect(soon.daysToExpiryOn(today), 10);
      expect(expired.daysToExpiryOn(today), -7);
    });

    test('JSON round trip with date fields', () {
      final batch = Batch(
        id: 'batch_001',
        productId: 'prod_001',
        batchNumber: 'BATCH-2026-001',
        expiryDate: DateTime(2026, 12, 30),
        quantity: 100,
        costPricePesewas: 850,
        sellingPricePesewas: 1454,
        receivedAt: DateTime.utc(2026, 8, 17, 10),
      );
      final restored = Batch.fromJson(batch.toJson());
      expect(restored.batchNumber, 'BATCH-2026-001');
      expect(restored.expiryDate, DateTime(2026, 12, 30));
      expect(restored.quantity, 100);
      expect(restored.receivedAt, DateTime.utc(2026, 8, 17, 10));
    });
  });

  group('Sale JSON round trip', () {
    test('items persist within sale', () {
      final sale = Sale(
        id: 'sale_001',
        operationId: 'op_001',
        invoiceNumber: 'INV-20260817-AB12-0042',
        sellerName: 'Kwame Appiah',
        totalAmountPesewas: 5000,
        createdAt: DateTime.utc(2026, 8, 17, 10, 42),
        items: const [
          SaleItem(
            id: 'si_1',
            saleId: 'sale_001',
            productId: 'prod_1',
            medicineName: 'Paracetamol 500mg',
            quantity: 2,
            unitPricePesewas: 1000,
            amountPesewas: 2000,
          ),
          SaleItem(
            id: 'si_2',
            saleId: 'sale_001',
            productId: 'prod_2',
            medicineName: 'ORS',
            quantity: 3,
            unitPricePesewas: 500,
            amountPesewas: 1500,
          ),
        ],
      );
      final restored = Sale.fromJson(sale.toJson());
      expect(restored.items.length, 2);
      expect(restored.items.first.amountPesewas, 2000);
      expect(restored.totalAmountPesewas, 5000);
      expect(restored.syncStatus, SyncStatus.pending);
    });
  });
}