import '../core/money.dart';
import '../data/local/local_store.dart';
import '../models/sale.dart';

/// Daily sales computations — always derived from committed local sales.
class DailySalesService {
  DailySalesService({required LocalStore store}) : _store = store;

  final LocalStore _store;

  /// Sales whose saleDate falls on [day].
  Future<List<Sale>> salesOn(DateTime day) => _store.getDailySales(day);

  Future<DailySalesSummary> summaryFor(DateTime day) async {
    final sales = await _store.getDailySales(day);
    var total = 0;
    var units = 0;
    for (final s in sales) {
      total += s.totalAmountPesewas;
      for (final item in s.items) {
        units += item.quantity;
      }
    }
    return DailySalesSummary(
      day: day,
      totalPesewas: total,
      transactions: sales.length,
      unitsSold: units,
      averageTransactionPesewas: sales.isEmpty ? 0 : (total / sales.length).round(),
    );
  }

  /// Sales in a date range (inclusive).
  Future<List<Sale>> salesBetween(DateTime from, DateTime to) =>
      _store.getSales(from: DateTime(from.year, from.month, from.day), to: DateTime(to.year, to.month, to.day, 23, 59, 59));
}

class DailySalesSummary {
  const DailySalesSummary({
    required this.day,
    required this.totalPesewas,
    required this.transactions,
    required this.unitsSold,
    required this.averageTransactionPesewas,
  });

  final DateTime day;
  final int totalPesewas;
  final int transactions;
  final int unitsSold;
  final int averageTransactionPesewas;

  Money get total => Money(totalPesewas);
  Money get averageTransaction => Money(averageTransactionPesewas);
}