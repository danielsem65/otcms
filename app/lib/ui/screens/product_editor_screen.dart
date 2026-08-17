import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/money.dart';
import '../../data/local/local_store.dart';
import '../../models/audit.dart';
import '../../models/product.dart';
import '../../state/providers.dart';

/// Add or edit a product in the local catalog.
class ProductEditorScreen extends ConsumerStatefulWidget {
  const ProductEditorScreen({super.key, this.product});

  final Product? product;

  @override
  ConsumerState<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends ConsumerState<ProductEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _genericName = TextEditingController(text: widget.product?.genericName ?? '');
  late final _brandName = TextEditingController(text: widget.product?.brandName ?? '');
  late final _category = TextEditingController(text: _categoryName);
  late final _dosageForm = TextEditingController(text: widget.product?.dosageForm ?? '');
  late final _strength = TextEditingController(text: widget.product?.strength ?? '');
  late final _packSize = TextEditingController(text: widget.product?.packSize ?? '');
  late final _barcode = TextEditingController(text: widget.product?.barcode ?? '');
  late final _sku = TextEditingController(text: widget.product?.sku ?? '');
  late final _manufacturer = TextEditingController(text: widget.product?.manufacturer ?? '');
  late final _responsible = TextEditingController(text: widget.product?.responsible ?? '');
  late final _sellingPrice =
      TextEditingController(text: widget.product == null ? '' : Money(widget.product!.sellingPricePesewas).formatPlain());
  late final _costPrice = TextEditingController(
      text: widget.product?.costPricePesewas == null ? '' : Money(widget.product!.costPricePesewas!).formatPlain());
  late final _reorderLevel =
      TextEditingController(text: widget.product?.reorderLevel.toString() ?? '');
  late final _minimumStock =
      TextEditingController(text: widget.product?.minimumStock.toString() ?? '');
  late final _targetStock =
      TextEditingController(text: widget.product?.targetStock.toString() ?? '');
  late final _reorderQuantity =
      TextEditingController(text: widget.product?.reorderQuantity.toString() ?? '');
  late bool _active = widget.product?.active ?? true;
  bool _saving = false;

  String get _categoryName {
    final product = widget.product;
    final categoryId = product?.categoryId;
    if (categoryId == null) return '';
    final categories = ref.read(_categoriesProvider).valueOrNull;
    if (categories == null) return '';
    for (final category in categories) {
      if (category.id == categoryId) return category.name;
    }
    return '';
  }

  @override
  void dispose() {
    _name.dispose();
    _genericName.dispose();
    _brandName.dispose();
    _category.dispose();
    _dosageForm.dispose();
    _strength.dispose();
    _packSize.dispose();
    _barcode.dispose();
    _sku.dispose();
    _manufacturer.dispose();
    _responsible.dispose();
    _sellingPrice.dispose();
    _costPrice.dispose();
    _reorderLevel.dispose();
    _minimumStock.dispose();
    _targetStock.dispose();
    _reorderQuantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saving = _saving;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.product == null ? 'New product' : 'Edit product'),
        actions: [
          TextButton(
            onPressed: saving ? null : _save,
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  key: const ValueKey('name'),
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Product name *'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('genericName'),
                  controller: _genericName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Generic name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('brandName'),
                  controller: _brandName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Brand name'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('category'),
                  controller: _category,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      labelText: 'Category', hintText: 'Type a name or pick a suggestion'),
                ),
                _CategorySuggestions(
                  query: _category.text,
                  onPick: (name) => setState(() {
                    _category.text = name;
                    _category.selection = TextSelection.collapsed(offset: name.length);
                  }),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('barcode'),
                  controller: _barcode,
                  decoration: const InputDecoration(labelText: 'Barcode'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('sku'),
                  controller: _sku,
                  decoration: const InputDecoration(labelText: 'SKU'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('sellingPrice'),
                        controller: _sellingPrice,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                        decoration: const InputDecoration(labelText: 'Selling price (₵) *'),
                        validator: (value) =>
                            (value == null || _pesewas(value) == null) ? 'Enter a valid price' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('costPrice'),
                        controller: _costPrice,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                        decoration: const InputDecoration(labelText: 'Cost price (₵)'),
                        validator: (value) =>
                            (value != null && value.trim().isNotEmpty && _pesewas(value) == null)
                                ? 'Enter a valid price'
                                : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('dosageForm'),
                        controller: _dosageForm,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Dosage form'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('strength'),
                        controller: _strength,
                        decoration: const InputDecoration(labelText: 'Strength'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('packSize'),
                        controller: _packSize,
                        decoration: const InputDecoration(labelText: 'Pack size'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('manufacturer'),
                        controller: _manufacturer,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Manufacturer'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('responsible'),
                  controller: _responsible,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Responsible'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('reorderLevel'),
                        controller: _reorderLevel,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Reorder level'),
                        validator: (value) =>
                            (value != null && value.trim().isNotEmpty && int.tryParse(value) == null)
                                ? 'Whole number'
                                : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('minimumStock'),
                        controller: _minimumStock,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Minimum stock'),
                        validator: (value) =>
                            (value != null && value.trim().isNotEmpty && int.tryParse(value) == null)
                                ? 'Whole number'
                                : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('targetStock'),
                        controller: _targetStock,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(labelText: 'Target stock'),
                        validator: (value) =>
                            (value != null && value.trim().isNotEmpty && int.tryParse(value) == null)
                                ? 'Whole number'
                                : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('reorderQuantity'),
                  controller: _reorderQuantity,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Reorder quantity'),
                  validator: (value) =>
                      (value != null && value.trim().isNotEmpty && int.tryParse(value) == null)
                          ? 'Whole number'
                          : null,
                ),
                SwitchListTile(
                  key: const ValueKey('active'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active (visible for sales)'),
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static int? _pesewas(String text) {
    final value = double.tryParse(text.trim());
    if (value == null) return null;
    return (value * 100).round();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final store = ref.read(localStoreProvider);
      final existing = widget.product;
      final now = DateTime.now().toUtc();
      final categoryId = await _resolveCategoryId(store);
      final product = existing == null
          ? Product(
              id: Ids.productId(),
              name: _name.text.trim(),
              genericName: _emptyToNull(_genericName.text),
              brandName: _emptyToNull(_brandName.text),
              categoryId: categoryId,
              dosageForm: _emptyToNull(_dosageForm.text),
              strength: _emptyToNull(_strength.text),
              packSize: _emptyToNull(_packSize.text),
              barcode: _emptyToNull(_barcode.text),
              sku: _emptyToNull(_sku.text),
              manufacturer: _emptyToNull(_manufacturer.text),
              responsible: _emptyToNull(_responsible.text),
              sellingPricePesewas: _pesewas(_sellingPrice.text)!,
              costPricePesewas: _emptyToNull(_costPrice.text) == null
                  ? null
                  : _pesewas(_costPrice.text),
              reorderLevel: _intOr(_reorderLevel.text, 10),
              minimumStock: _intOr(_minimumStock.text, 5),
              targetStock: _intOr(_targetStock.text, 50),
              reorderQuantity: _intOr(_reorderQuantity.text, 20),
              active: _active,
              createdAt: now,
            )
          : existing.copyWith(
              name: _name.text.trim(),
              genericName: _emptyToNull(_genericName.text),
              brandName: _emptyToNull(_brandName.text),
              categoryId: categoryId,
              dosageForm: _emptyToNull(_dosageForm.text),
              strength: _emptyToNull(_strength.text),
              packSize: _emptyToNull(_packSize.text),
              barcode: _emptyToNull(_barcode.text),
              sku: _emptyToNull(_sku.text),
              manufacturer: _emptyToNull(_manufacturer.text),
              responsible: _emptyToNull(_responsible.text),
              sellingPricePesewas: _pesewas(_sellingPrice.text)!,
              costPricePesewas: _emptyToNull(_costPrice.text) == null
                  ? null
                  : _pesewas(_costPrice.text),
              reorderLevel: _intOr(_reorderLevel.text, 10),
              minimumStock: _intOr(_minimumStock.text, 5),
              targetStock: _intOr(_targetStock.text, 50),
              reorderQuantity: _intOr(_reorderQuantity.text, 20),
              active: _active,
              updatedAt: now,
            );
      await store.putProduct(product);
      await ref.read(auditServiceProvider).log(AuditLog(
        id: '',
        action: existing == null ? AuditLog.productCreated : AuditLog.productUpdated,
        entity: 'product',
        entityId: product.id,
        before: existing?.toJson(),
        after: product.toJson(),
      ));
      if (!mounted) return;
      Navigator.of(context).pop(product);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _resolveCategoryId(LocalStore store) async {
    final name = _category.text.trim();
    if (name.isEmpty) return null;
    final categories = await store.getCategories();
    for (final category in categories) {
      if (category.name.toLowerCase() == name.toLowerCase()) return category.id;
    }
    final category = Category(id: Ids.categoryId(), name: name);
    await store.putCategory(category);
    return category.id;
  }

  static int _intOr(String text, int fallback) => int.tryParse(text.trim()) ?? fallback;

  static String? _emptyToNull(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _CategorySuggestions extends ConsumerWidget {
  const _CategorySuggestions({required this.query, required this.onPick});

  final String query;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const SizedBox.shrink();
    final categories = ref.watch(_categoriesProvider).valueOrNull ?? const <Category>[];
    final matches = categories.where((c) => c.name.toLowerCase().contains(q)).toList();
    if (matches.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final category in matches)
            ActionChip(
              label: Text(category.name),
              onPressed: () => onPick(category.name),
            ),
        ],
      ),
    );
  }
}

final _categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final store = ref.watch(localStoreProvider);
  return store.getCategories();
});