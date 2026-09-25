import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../models/batch.dart';
import '../../models/product.dart';
import '../../services/csv_export_service.dart';
import '../../services/inventory_service.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'product_editor_screen.dart';

/// Product catalog with fast search (works offline).
///
/// Doubles as the inventory view: each row shows live sellable stock and a
/// status derived from the configured thresholds.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _importing = false;
  bool _exporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(_productsProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
            tooltip: 'Export products to CSV (Excel)',
            onPressed: _exporting ? null : _exportCsv,
          ),
          IconButton(
            icon: _importing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            tooltip: 'Import products from JSON',
            onPressed: _importing ? null : _importFromFile,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New product',
            onPressed: () => _openEditor(context, null),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search by name, brand, barcode, SKU…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
        ),
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          if (rows.isEmpty) {
            return Center(
              child: Text(_query.isEmpty
                  ? 'No products yet. Import the pharmacy product list from Settings.'
                  : 'No products match "$_query".'),
            );
          }
          final wide = MediaQuery.sizeOf(context).width >= 900;
          if (wide) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Product')),
                    DataColumn(label: Text('Stock')),
                    DataColumn(label: Text('Selling Price')),
                    DataColumn(label: Text('Responsible')),
                    DataColumn(label: Text('Barcode')),
                    DataColumn(label: Text('Status')),
                  ],
                  rows: [
                    for (final row in rows)
                      DataRow(
                        onSelectChanged: (_) => _openEditor(context, row.product),
                        cells: [
                          DataCell(SizedBox(
                            width: 320,
                            child: Text(row.product.name,
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w600)),
                          )),
                          DataCell(_stockCell(row)),
                          DataCell(Text(_price(row.product),
                              style: const TextStyle(fontWeight: FontWeight.w700))),
                          DataCell(Text(row.product.responsible ?? '—')),
                          DataCell(Text(row.product.barcode ?? '—')),
                          DataCell(
                            row.product.active
                                ? const Icon(Icons.check_circle,
                                    color: OtcmsTheme.safe, size: 18)
                                : const Icon(Icons.block,
                                    color: OtcmsTheme.danger, size: 18),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, i) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final row = rows[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: OtcmsTheme.seed.withOpacity(0.12),
                    child: const Icon(Icons.medication, color: OtcmsTheme.seed),
                  ),
                  title: Text(row.product.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${row.product.responsible ?? ''} · ${_stockLabel(row)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_price(row.product),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('${row.stock} in stock',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _stockColor(row.level))),
                    ],
                  ),
                  onTap: () => _openEditor(context, row.product),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _price(Product p) {
    final symbol = ref.watch(settingsProvider).valueOrNull?.currencySymbol ?? '₵';
    return Money(p.sellingPricePesewas).format(symbol: symbol);
  }

  String _stockLabel(ProductStockRow row) =>
      '${row.stock} in stock · ${row.level.label}';

  Widget _stockCell(ProductStockRow row) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${row.stock}',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _stockColor(row.level))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _stockColor(row.level).withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(row.level.label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _stockColor(row.level))),
        ),
      ],
    );
  }

  static Color _stockColor(StockLevel level) => switch (level) {
        StockLevel.healthy => OtcmsTheme.safe,
        StockLevel.low => OtcmsTheme.warning,
        StockLevel.critical => OtcmsTheme.caution,
        StockLevel.outOfStock => OtcmsTheme.danger,
      };

  Future<void> _importFromFile() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = picked?.files.single.path;
      if (path == null) return;

      final raw = await File(path).readAsString();
      final outcome = await ref.read(productImportServiceProvider).importJson(raw);
      if (!mounted) return;
      if (outcome.isOk) {
        final summary = outcome.value;
        ref.invalidate(_productsProvider(_query));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Imported ${summary.imported} products (${summary.skippedInvalid} skipped).'),
        ));
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(outcome.error.message)));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final products = await ref.read(localStoreProvider).getProducts();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export products to CSV',
        fileName: 'otcms-products.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (path == null) return;
      await File(path).writeAsString(CsvExport.productsCsv(products));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Products exported to CSV.')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _openEditor(BuildContext context, Product? product) {
    Navigator.of(context)
        .push<Product>(MaterialPageRoute(
          builder: (_) => ProductEditorScreen(product: product),
        ))
        .then((saved) {
      if (!context.mounted) return;
      if (saved != null) {
        ref.invalidate(_productsProvider(_query));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${saved.name}" saved.')),
        );
      }
    });
  }
}

/// Product row enriched with live stock info for the inventory view.
class ProductStockRow {
  const ProductStockRow({
    required this.product,
    required this.stock,
    required this.level,
  });

  final Product product;
  final int stock;
  final StockLevel level;
}

final _productsProvider =
    FutureProvider.family<List<ProductStockRow>, String>((ref, query) async {
  final store = ref.watch(localStoreProvider);
  final products = await store.getProducts(search: query);
  final batches = await store.getBatches();
  final grouped = <String, List<Batch>>{};
  for (final batch in batches) {
    grouped.putIfAbsent(batch.productId, () => []).add(batch);
  }
  const inventory = InventoryService();
  final today = DateTime.now();
  return [
    for (final product in products)
      ProductStockRow(
        product: product,
        stock: inventory.sellableStock(grouped[product.id] ?? const [], today),
        level: inventory.stockLevelFor(
          batches: grouped[product.id] ?? const [],
          product: product,
          today: today,
        ),
      ),
  ];
});