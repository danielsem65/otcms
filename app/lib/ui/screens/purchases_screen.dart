import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../models/purchase.dart';
import '../../models/supplier.dart';
import '../../services/csv_export_service.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'purchase_editor_screen.dart';

/// Purchase invoices list — desktop table with search + status filter,
/// mobile card list. Tapping an invoice opens the editor (read-only when
/// already received).
class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

enum _StatusFilter {
  all('All'),
  draft('Draft'),
  ordered('Ordered'),
  received('Received'),
  cancelled('Cancelled');

  const _StatusFilter(this.label);
  final String label;

  PurchaseStatus? get status => switch (this) {
        _StatusFilter.all => null,
        _StatusFilter.draft => PurchaseStatus.draft,
        _StatusFilter.ordered => PurchaseStatus.ordered,
        _StatusFilter.received => PurchaseStatus.received,
        _StatusFilter.cancelled => PurchaseStatus.cancelled,
      };
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _StatusFilter _filter = _StatusFilter.all;
  bool _exporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final purchasesAsync = ref.watch(_purchasesProvider(_query));
    final suppliers =
        ref.read(_suppliersProvider).valueOrNull ?? const <Supplier>[];
    final supplierNames = {for (final s in suppliers) s.id: s.name};

    var totalSpend = 0;
    var receivedCount = 0;
    for (final p in purchasesAsync.valueOrNull ?? const <Purchase>[]) {
      if (p.status == PurchaseStatus.received) {
        receivedCount++;
        totalSpend += p.totalCostPesewas;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchases'),
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
            tooltip: 'Export to CSV (Excel)',
            onPressed: _exporting ? null : _exportCsv,
          ),
          FilledButton.icon(
            onPressed: () => _openEditor(context, null),
            icon: const Icon(Icons.add),
            label: const Text('New Invoice'),
          ),
          const SizedBox(width: 16),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      hintText: 'Search by invoice no or supplier…',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<_StatusFilter>(
                    key: const ValueKey('statusFilter'),
                    value: _filter,
                    decoration: const InputDecoration(
                        labelText: 'Status', isDense: true),
                    items: [
                      for (final f in _StatusFilter.values)
                        DropdownMenuItem(value: f, child: Text(f.label)),
                    ],
                    onChanged: (value) =>
                        setState(() => _filter = value ?? _StatusFilter.all),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: purchasesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          final purchases = [
            for (final p in all)
              if (_filter.status == null || p.status == _filter.status) p
          ];
          if (purchases.isEmpty) {
            return Center(
              child: Text(_query.isEmpty && _filter == _StatusFilter.all
                  ? 'No invoices yet. Create your first purchase invoice to receive stock.'
                  : 'No invoices match your filters.'),
            );
          }
          final wide = MediaQuery.sizeOf(context).width >= 900;
          if (wide) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _StatChip(
                          label: 'RECEIVED INVOICES', value: '$receivedCount'),
                      const SizedBox(width: 12),
                      _StatChip(
                          label: 'TOTAL SPENT',
                          value: Money(totalSpend).format()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Invoice')),
                        DataColumn(label: Text('Supplier')),
                        DataColumn(label: Text('Date')),
                        DataColumn(label: Text('Items')),
                        DataColumn(label: Text('Total')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: [
                        for (final p in purchases)
                          DataRow(
                            onSelectChanged: (_) => _openEditor(context, p),
                            cells: [
                              DataCell(Text(p.purchaseNumber,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                              DataCell(Text(_supplierName(p, supplierNames))),
                              DataCell(Text(_formatDay(p.createdAt))),
                              DataCell(Text('${p.items.length}')),
                              DataCell(Text(Money(p.totalCostPesewas).format(),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700))),
                              DataCell(_statusChip(p.status)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: purchases.length + 2,
            separatorBuilder: (_, i) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Row(
                  children: [
                    _StatChip(label: 'RECEIVED', value: '$receivedCount'),
                    const SizedBox(width: 12),
                    _StatChip(
                        label: 'TOTAL SPENT',
                        value: Money(totalSpend).format()),
                  ],
                );
              }
              if (i == 1) return const Divider();
              final p = purchases[i - 2];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: OtcmsTheme.seed.withOpacity(0.12),
                    child: const Icon(Icons.shopping_cart_outlined,
                        color: OtcmsTheme.seed),
                  ),
                  title: Text(p.purchaseNumber,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${_supplierName(p, supplierNames)} · ${_formatDay(p.createdAt)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _statusChip(p.status),
                      const SizedBox(width: 6),
                      Text(Money(p.totalCostPesewas).format(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                    ],
                  ),
                  onTap: () => _openEditor(context, p),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, Purchase? purchase) async {
    final result = await Navigator.of(context).push<PurchaseEditorResult>(
      MaterialPageRoute(
        builder: (_) => PurchaseEditorScreen(purchase: purchase),
      ),
    );
    if (!context.mounted) return;
    if (result != null) {
      ref.invalidate(_purchasesProvider(_query));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.received
            ? '${result.purchase.purchaseNumber} received — stock updated.'
            : '${result.purchase.purchaseNumber} saved as draft.'),
      ));
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final supplierNames = {
        for (final s in ref.read(_suppliersProvider).valueOrNull ?? const <Supplier>[])
          s.id: s.name
      };
      final purchases = await ref.read(localStoreProvider).getPurchases();
      final symbol =
          ref.read(settingsProvider).valueOrNull?.currencySymbol ?? 'GH₵';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export purchases to CSV',
        fileName: 'otcms-purchases.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (path == null) return;
      await File(path).writeAsString(
          CsvExport.purchasesCsv(purchases, supplierNames,
              currencyCode: symbol));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchases exported to CSV.')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  static String _supplierName(
          Purchase purchase, Map<String, String> supplierNames) =>
      purchase.supplierId == null
          ? '—'
          : supplierNames[purchase.supplierId] ?? 'Unknown';

  static String _formatDay(DateTime? date) {
    if (date == null) return '—';
    final d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  static Widget _statusChip(PurchaseStatus status) {
    final (label, color) = switch (status) {
      PurchaseStatus.draft => ('DRAFT', const Color(0xFF607D8B)),
      PurchaseStatus.ordered => ('ORDERED', OtcmsTheme.caution),
      PurchaseStatus.received => ('RECEIVED', OtcmsTheme.safe),
      PurchaseStatus.cancelled => ('CANCELLED', OtcmsTheme.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: ',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700])),
            Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: OtcmsTheme.seed)),
          ],
        ),
      ),
    );
  }
}

final _purchasesProvider = FutureProvider.family<List<Purchase>, String>((ref, query) async {
  final store = ref.watch(localStoreProvider);
  final purchases = await store.getPurchases();
  purchases.sort((a, b) {
    final ta = a.createdAt ?? DateTime(0);
    final tb = b.createdAt ?? DateTime(0);
    return tb.compareTo(ta);
  });
  final cleanQuery = query.trim().toLowerCase();
  if (cleanQuery.isEmpty) return purchases;
  final suppliers = await store.getSuppliers();
  final supplierNames = {for (final s in suppliers) s.id: s.name.toLowerCase()};
  return [
    for (final p in purchases)
      if (p.purchaseNumber.toLowerCase().contains(cleanQuery) ||
          (p.supplierId != null &&
              (supplierNames[p.supplierId]?.contains(cleanQuery) ?? false)))
        p
  ];
});

final _suppliersProvider = FutureProvider<List<Supplier>>((ref) async {
  final store = ref.watch(localStoreProvider);
  return store.getSuppliers();
});