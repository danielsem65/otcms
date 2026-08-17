import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/models/batch.dart';
import 'package:otcms/models/product.dart';
import 'package:otcms/services/inventory_service.dart';

Product product(String id, {int reorderLevel = 10, int minimumStock = 5}) => Product(
      id: id,
      name: 'Product $id',
      sellingPricePesewas: 1000,
      reorderLevel: reorderLevel,
      minimumStock: minimumStock,
    );

Batch batch(String id, int quantity, {DateTime? expiry, DateTime? receivedAt}) =>
    Batch(
      id: id,
      productId: 'p1',
      quantity: quantity,
      expiryDate: expiry,
      receivedAt: receivedAt,
    );

void main() {
  final today = DateTime(2026, 8, 17);
  const service = InventoryService();

  group('InventoryService — sellable stock & FEFO', () {
    test('expired batches are excluded from sellable stock', () {
      final batches = [
        batch('b1', 40, expiry: DateTime(2026, 8, 10)),
        batch('b2', 10, expiry: DateTime(2026, 8, 20)),
        batch('b3', 5),
      ];
      expect(service.sellableStock(batches, today), 15);
      expect(service.totalStock(batches), 55);
    });

    test('FEFO allocates soonest-expiring first, undated last', () {
      final batches = [
        batch('b3', 10),
        batch('b2', 10, expiry: DateTime(2026, 9, 1)),
        batch('b1', 10, expiry: DateTime(2026, 8, 25)),
      ];
      final allocation = service.allocateFefo(batches: batches, quantity: 25, today: today);
      expect(allocation.isFullyAllocated, isTrue);
      expect(allocation.batches.map((e) => e.$1.id).toList(), ['b1', 'b2', 'b3']);
      expect(allocation.batches[0].$2, 10);
      expect(allocation.batches[1].$2, 10);
      expect(allocation.batches[2].$2, 5);
    });

    test('expired batches are never allocated for sales', () {
      final batches = [
        batch('b1', 40, expiry: DateTime(2026, 8, 10)),
        batch('b2', 10, expiry: DateTime(2026, 8, 20)),
      ];
      final allocation = service.allocateFefo(batches: batches, quantity: 35, today: today);
      expect(allocation.batches.map((e) => e.$1.id).toList(), ['b2']);
      expect(allocation.unallocatedQuantity, 25);
      expect(allocation.isFullyAllocated, isFalse);
    });

    test('allowExpired permits allocation of expired stock', () {
      final batches = [
        batch('b1', 40, expiry: DateTime(2026, 8, 10)),
      ];
      final allocation = service.allocateFefo(
        batches: batches,
        quantity: 10,
        today: today,
        allowExpired: true,
      );
      expect(allocation.batches.single.$1.id, 'b1');
      expect(allocation.isFullyAllocated, isTrue);
    });
  });

  group('InventoryService — stock levels', () {
    test('classifies levels relative to thresholds', () {
      expect(
        service.stockLevelFor(batches: [], product: product('p'), today: today),
        StockLevel.outOfStock,
      );
      expect(
        service.stockLevelFor(
          batches: [batch('b1', 3)],
          product: product('p', reorderLevel: 10, minimumStock: 5),
          today: today,
        ),
        StockLevel.critical,
      );
      expect(
        service.stockLevelFor(
          batches: [batch('b1', 8)],
          product: product('p', reorderLevel: 10, minimumStock: 5),
          today: today,
        ),
        StockLevel.low,
      );
      expect(
        service.stockLevelFor(
          batches: [batch('b1', 30)],
          product: product('p', reorderLevel: 10, minimumStock: 5),
          today: today,
        ),
        StockLevel.healthy,
      );
    });
  });

  group('InventoryService — expiry buckets', () {
    const warningDays = [7, 30, 60, 90, 180];

    test('classifies batches into the right buckets', () {
      expect(
        service.expiryBucketFor(batch('b1', 1, expiry: DateTime(2026, 8, 10)), today, warningDays),
        ExpiryBucket.expired,
      );
      expect(
        service.expiryBucketFor(batch('b2', 1, expiry: DateTime(2026, 8, 20)), today, warningDays),
        ExpiryBucket.sevenDays,
      );
      expect(
        service.expiryBucketFor(batch('b3', 1, expiry: DateTime(2026, 8, 27)), today, warningDays),
        ExpiryBucket.thirtyDays,
      );
      expect(
        service.expiryBucketFor(batch('b4', 1, expiry: DateTime(2026, 9, 30)), today, warningDays),
        ExpiryBucket.sixtyDays,
      );
      expect(
        service.expiryBucketFor(batch('b5', 1, expiry: DateTime(2026, 11, 15)), today, warningDays),
        ExpiryBucket.ninetyDays,
      );
      expect(
        service.expiryBucketFor(batch('b6', 1, expiry: DateTime(2027, 3, 1)), today, warningDays),
        ExpiryBucket.safe,
      );
      expect(
        service.expiryBucketFor(batch('b7', 1), today, warningDays),
        ExpiryBucket.safe,
      );
    });
  });
}