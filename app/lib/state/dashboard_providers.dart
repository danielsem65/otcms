import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/batch.dart';
import '../models/notification.dart';
import '../models/sale.dart';
import '../services/daily_sales_service.dart';
import '../services/inventory_service.dart';
import 'providers.dart';

/// Real dashboard numbers, computed from local data on every refresh.
class DashboardModel {
  const DashboardModel({
    required this.settingsReady,
    required this.todaySalesPesewas,
    required this.todayTransactions,
    required this.todayUnitsSold,
    required this.inventoryValuePesewas,
    required this.productCount,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.expiringSoonCount,
    required this.expiredCount,
    required this.gettingFinished,
    required this.topSelling,
    required this.expiryAlertCounts,
  });

  static const empty = DashboardModel(
    settingsReady: false,
    todaySalesPesewas: 0,
    todayTransactions: 0,
    todayUnitsSold: 0,
    inventoryValuePesewas: 0,
    productCount: 0,
    lowStockCount: 0,
    outOfStockCount: 0,
    expiringSoonCount: 0,
    expiredCount: 0,
    gettingFinished: [],
    topSelling: [],
    expiryAlertCounts: {},
  );

  final bool settingsReady;
  final int todaySalesPesewas;
  final int todayTransactions;
  final int todayUnitsSold;
  final int inventoryValuePesewas;
  final int productCount;
  final int lowStockCount;
  final int outOfStockCount;
  final int expiringSoonCount;
  final int expiredCount;
  final List<(String name, int stock, bool critical)> gettingFinished;
  final List<(String name, int units)> topSelling;
  final Map<ExpiryBucket, int> expiryAlertCounts;
}

final dashboardProvider = FutureProvider<DashboardModel>((ref) async {
  final store = ref.watch(localStoreProvider);
  final settings = await store.getSettings();
  final today = DateTime.now();

  final sales = await store.getDailySales(today);
  var salesTotal = 0;
  var units = 0;
  final unitsByProduct = <String, int>{};
  for (final s in sales) {
    salesTotal += s.totalAmountPesewas;
    for (final item in s.items) {
      units += item.quantity;
      unitsByProduct.update(item.productId, (v) => v + item.quantity, ifAbsent: () => item.quantity);
    }
  }

  final products = await store.getProducts(activeOnly: true);
  final batches = await store.getBatches();
  final byProduct = <String, List<Batch>>{};
  for (final b in batches) {
    byProduct.putIfAbsent(b.productId, () => []).add(b);
  }

  final service = const InventoryService();
  var lowStock = 0;
  var outOfStock = 0;
  var inventoryValue = 0;
  final gettingFinished = <(String, int, bool)>[];

  for (final p in products) {
    final pb = byProduct[p.id] ?? const <Batch>[];
    final stock = service.sellableStock(pb, today);
    final level = service.stockLevelFor(batches: pb, product: p, today: today);
    if (level == StockLevel.low || level == StockLevel.critical) lowStock++;
    if (level == StockLevel.outOfStock) outOfStock++;
    inventoryValue += stock * (p.costPricePesewas ?? p.sellingPricePesewas);
    if (stock > 0 && stock <= p.reorderLevel) {
      gettingFinished.add((p.name, stock, level == StockLevel.critical));
    }
  }
  gettingFinished.sort((a, b) => a.$2.compareTo(b.$2));

  // Expiry buckets.
  final expiryCounts = <ExpiryBucket, int>{};
  for (final b in batches) {
    final bucket = service.expiryBucketFor(b, today, settings.expiryWarningDays);
    if (bucket != ExpiryBucket.safe) {
      expiryCounts.update(bucket, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  final expiringSoon = (expiryCounts[ExpiryBucket.sevenDays] ?? 0) +
      (expiryCounts[ExpiryBucket.thirtyDays] ?? 0) +
      (expiryCounts[ExpiryBucket.sixtyDays] ?? 0) +
      (expiryCounts[ExpiryBucket.ninetyDays] ?? 0) +
      (expiryCounts[ExpiryBucket.oneEightyDays] ?? 0);

  // Top selling today.
  final nameByProduct = {for (final p in products) p.id: p.name};
  final topSelling = unitsByProduct.entries
      .map((e) => (nameByProduct[e.key] ?? e.key, e.value))
      .toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));

  return DashboardModel(
    settingsReady: true,
    todaySalesPesewas: salesTotal,
    todayTransactions: sales.length,
    todayUnitsSold: units,
    inventoryValuePesewas: inventoryValue,
    productCount: products.length,
    lowStockCount: lowStock,
    outOfStockCount: outOfStock,
    expiringSoonCount: expiringSoon,
    expiredCount: expiryCounts[ExpiryBucket.expired] ?? 0,
    gettingFinished: gettingFinished.take(8).toList(),
    topSelling: topSelling.take(5).toList(),
    expiryAlertCounts: expiryCounts,
  );
});

final salesTodayProvider = FutureProvider.autoDispose<DailySalesSummary>((ref) async {
  final store = ref.watch(localStoreProvider);
  return DailySalesService(store: store).summaryFor(DateTime.now());
});

/// List of unread notifications.
final unreadNotificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final store = ref.watch(localStoreProvider);
  return store.getUnreadNotifications();
});