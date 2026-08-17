import '../models/batch.dart';
import '../models/product.dart';

/// Stock status for a product.
enum StockLevel {
  healthy,
  low,
  critical,
  outOfStock;

  String get label => switch (this) {
        StockLevel.healthy => 'HEALTHY',
        StockLevel.low => 'LOW STOCK',
        StockLevel.critical => 'CRITICAL',
        StockLevel.outOfStock => 'OUT OF STOCK',
      };
}

/// Result of FEFO allocation for a product.
class FefoAllocation {
  const FefoAllocation({
    required this.batches,
    required this.unallocatedQuantity,
  });

  /// Allocated (batch, quantityFromBatch) pairs in expiry order.
  final List<(Batch, int)> batches;

  /// Quantity that could not be allocated (insufficient sellable stock).
  final int unallocatedQuantity;

  bool get isFullyAllocated => unallocatedQuantity == 0;
}

/// Pure inventory domain logic.
///
/// Stock is always derived from movements applied to batches; this
/// service implements FEFO selection, stock status, and sellable stock.
class InventoryService {
  const InventoryService();

  /// Sellable stock for [batches] on [today]: sum of quantities of
  /// batches that have not expired.
  int sellableStock(List<Batch> batches, DateTime today) {
    var total = 0;
    for (final b in batches) {
      if (b.hasExpiry && b.isExpiredOn(today)) continue;
      total += b.quantity;
    }
    return total;
  }

  /// Total stock including expired batches (for reports/visibility).
  int totalStock(List<Batch> batches) =>
      batches.fold(0, (sum, b) => sum + b.quantity);

  /// Stock level relative to thresholds.
  StockLevel stockLevelFor({
    required List<Batch> batches,
    required Product product,
    required DateTime today,
  }) {
    final stock = sellableStock(batches, today);
    if (stock <= 0) return StockLevel.outOfStock;
    if (stock <= product.minimumStock) return StockLevel.critical;
    if (stock <= product.reorderLevel) return StockLevel.low;
    return StockLevel.healthy;
  }

  /// FEFO: allocate [quantity] units from [batches], always using the
  /// batch with the earliest valid expiry first. Expired batches are
  /// never used for normal sales. Null expiry dates sort last (newest
  /// arrival first among them, since they have no expiry constraint).
  FefoAllocation allocateFefo({
    required List<Batch> batches,
    required int quantity,
    required DateTime today,
    bool allowExpired = false,
  }) {
    final usable = batches.where((b) {
      if (b.quantity <= 0) return false;
      if (!allowExpired && b.hasExpiry && b.isExpiredOn(today)) return false;
      return true;
    }).toList();

    usable.sort((a, b) {
      final ae = a.expiryDate;
      final be = b.expiryDate;
      if (ae == null && be == null) return a.receivedAt?.compareTo(b.receivedAt ?? DateTime(0)) ?? 0;
      if (ae == null) return 1;
      if (be == null) return -1;
      final byExpiry = ae.compareTo(be);
      if (byExpiry != 0) return byExpiry;
      return a.receivedAt?.compareTo(b.receivedAt ?? DateTime(0)) ?? 0;
    });

    final allocations = <(Batch, int)>[];
    var remaining = quantity;
    for (final batch in usable) {
      if (remaining <= 0) break;
      final take = remaining < batch.quantity ? remaining : batch.quantity;
      allocations.add((batch, take));
      remaining -= take;
    }
    return FefoAllocation(batches: allocations, unallocatedQuantity: remaining);
  }

  /// Expiry bucket for a batch on [today].
  ExpiryBucket expiryBucketFor(Batch batch, DateTime today, List<int> warningDays) {
    if (!batch.hasExpiry) return ExpiryBucket.safe;
    if (batch.isExpiredOn(today)) return ExpiryBucket.expired;
    final days = batch.daysToExpiryOn(today);
    for (final threshold in warningDays) {
      if (days <= threshold) return ExpiryBucket.expiringWithin(threshold);
    }
    return ExpiryBucket.safe;
  }
}

/// Expiry buckets matching the configured thresholds.
enum ExpiryBucket {
  expired,
  sevenDays,
  thirtyDays,
  sixtyDays,
  ninetyDays,
  oneEightyDays,
  safe;

  static ExpiryBucket expiringWithin(int days) => switch (days) {
        <= 7 => ExpiryBucket.sevenDays,
        <= 30 => ExpiryBucket.thirtyDays,
        <= 60 => ExpiryBucket.sixtyDays,
        <= 90 => ExpiryBucket.ninetyDays,
        _ => ExpiryBucket.oneEightyDays,
      };

  bool get isExpired => this == ExpiryBucket.expired;
}