import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../models/product.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// Product catalog with fast search (works offline).
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(_productsProvider(_query));
    final settings = ref.watch(settingsProvider).valueOrNull;
    final symbol = settings?.currencySymbol ?? '₵';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
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
        data: (products) {
          if (products.isEmpty) {
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
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Responsible')),
                  DataColumn(label: Text('Barcode')),
                  DataColumn(label: Text('Selling Price')),
                  DataColumn(label: Text('Status')),
                ],
                rows: [
                  for (final p in products)
                    DataRow(
                      onSelectChanged: (_) => _openEditor(context, p),
                      cells: [
                        DataCell(SizedBox(
                          width: 340,
                          child: Text(p.name,
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        )),
                        DataCell(Text(p.responsible ?? '—')),
                        DataCell(Text(p.barcode ?? '—')),
                        DataCell(Text(Money(p.sellingPricePesewas).format(symbol: symbol),
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(p.active
                            ? const Icon(Icons.check_circle, color: OtcmsTheme.safe, size: 18)
                            : const Icon(Icons.block, color: OtcmsTheme.danger, size: 18)),
                      ],
                    ),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = products[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: OtcmsTheme.seed.withOpacity(0.12),
                    child: const Icon(Icons.medication, color: OtcmsTheme.seed),
                  ),
                  title: Text(p.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(p.responsible ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(Money(p.sellingPricePesewas).format(symbol: symbol),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  onTap: () => _openEditor(context, p),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openEditor(BuildContext context, Product? product) {
    if (product != null) {
      // Product details/edit lands with the product management phase;
      // the dialog gives immediate visibility for now.
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(product.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.responsible != null) Text('Responsible: ${product.responsible}'),
              Text('Selling price: ₵${Money(product.sellingPricePesewas).formatPlain()}'),
              if (product.barcode != null) Text('Barcode: ${product.barcode}'),
              if (product.categoryId != null) Text('Category: ${product.categoryId}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product creation ships with the product management phase.')),
      );
    }
  }
}

final _productsProvider = FutureProvider.family<List<Product>, String>((ref, query) async {
  final store = ref.watch(localStoreProvider);
  return store.getProducts(search: query);
});