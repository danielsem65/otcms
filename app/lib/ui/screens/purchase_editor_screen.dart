import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ids.dart';
import '../../core/money.dart';
import '../../data/local/local_store.dart';
import '../../models/product.dart';
import '../../models/purchase.dart';
import '../../models/supplier.dart';
import '../../services/purchase_service.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/product_search_field.dart';

/// Result popped by [PurchaseEditorScreen].
class PurchaseEditorResult {
  const PurchaseEditorResult({required this.purchase, required this.received});
  final Purchase purchase;
  final bool received;
}

/// Desktop Add/Edit/View invoice page.
///
/// Layout adapts to screen width: narrow devices stack the supplier/notes
/// panel above the items; wide screens show them side by side.
class PurchaseEditorScreen extends ConsumerStatefulWidget {
  const PurchaseEditorScreen({super.key, this.purchase});

  final Purchase? purchase;

  @override
  ConsumerState<PurchaseEditorScreen> createState() =>
      _PurchaseEditorScreenState();
}

class _EditorLine {
  _EditorLine({
    required this.id,
    this.productId,
    required String name,
    int quantity = 1,
    int costPricePesewas = 0,
    this.batchNumber,
    this.expiryDate,
  }) {
    this.name = name;
    qtyController = TextEditingController(text: '$quantity');
    costController = TextEditingController(
        text: costPricePesewas == 0 ? '' : Money(costPricePesewas).formatPlain());
  }

  final String id;
  String? productId;
  late String name;
  final TextEditingController qtyController;
  final TextEditingController costController;
  String? batchNumber;
  DateTime? expiryDate;

  int get amountPesewas {
    final qty = int.tryParse(qtyController.text.trim()) ?? 0;
    final cost = Money.tryParse(costController.text)?.pesewas ?? 0;
    return qty * cost;
  }
}

class _PurchaseEditorScreenState extends ConsumerState<PurchaseEditorScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _invoiceNo = TextEditingController();
  late final _notes = TextEditingController(text: widget.purchase?.notes ?? '');
  late final _dateController = TextEditingController();
  late final _lineControllers = <String, _EditorLine>{};
  final _productController = TextEditingController();
  final _productFocusNode = FocusNode();
  final _newQtyController = TextEditingController(text: '1');
  final _newCostController = TextEditingController();
  final _newBatchController = TextEditingController();
  final _newExpiryController = TextEditingController();

  String? _supplierId;
  String? _pendingSupplierName;
  DateTime? _date;
  bool _saving = false;

  Purchase? get existing => widget.purchase;

  bool get _viewOnly =>
      existing != null &&
      (existing!.status == PurchaseStatus.received ||
          existing!.status == PurchaseStatus.cancelled);

  @override
  void initState() {
    super.initState();
    _date = existing?.createdAt?.toLocal() ?? DateTime.now();
    _dateController.text = _formatDay(_date!);
    _supplierId = existing?.supplierId;
    final purchase = existing;
    if (purchase != null) {
      _invoiceNo.text = purchase.purchaseNumber;
      for (final item in purchase.items) {
        final line = _EditorLine(
          id: Ids.newId('l'),
          productId: item.productId,
          name: '',
          quantity: item.quantity,
          costPricePesewas: item.costPricePesewas,
          batchNumber: item.batchNumber,
          expiryDate: item.expiryDate,
        );
        _lineControllers[line.id] = line;
      }
    } else {
      _invoiceNo.text = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fillNextInvoiceNumber();
      });
    }
  }

  Future<void> _fillNextInvoiceNumber() async {
    final number =
        await ref.read(purchaseServiceProvider).nextPurchaseNumber();
    if (!mounted) return;
    setState(() => _invoiceNo.text = number);
  }

  @override
  void dispose() {
    _invoiceNo.dispose();
    _notes.dispose();
    _dateController.dispose();
    _productController.dispose();
    _productFocusNode.dispose();
    _newQtyController.dispose();
    _newCostController.dispose();
    _newBatchController.dispose();
    _newExpiryController.dispose();
    for (final line in _lineControllers.values) {
      line.qtyController.dispose();
      line.costController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider).valueOrNull ?? const <Product>[];
    final productsByName = {for (final p in catalog) p.id: p.name};
    // Resolve names for lines that were loaded from an existing purchase.
    for (final line in _lineControllers.values) {
      if (line.name.isEmpty) {
        line.name = productsByName[line.productId] ?? line.productId ?? 'Unknown item';
      }
    }

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final title = existing == null
        ? 'New Invoice'
        : 'Invoice ${existing!.purchaseNumber}';
    final subtitle = existing == null
        ? 'Goods receipt / purchase order'
        : _viewOnly
            ? '${existing!.status.label} — read only'
            : '${existing!.status.label} — editable draft';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        actions: [
          if (existing != null) ...[
            _StatusChip(status: existing!.status),
            const SizedBox(width: 12),
          ],
          if (!_viewOnly) ...[
            OutlinedButton.icon(
              key: const ValueKey('saveDraftButton'),
              onPressed: _saving ? null : () => _save(draft: true),
              icon: const Icon(Icons.drafts_outlined),
              label: const Text('Save Draft'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('receiveButton'),
              onPressed: _saving ? null : () => _save(draft: false),
              icon: const Icon(Icons.inventory_2),
              label: const Text('Save & Receive'),
            ),
          ] else ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
          const SizedBox(width: 16),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: wide ? _buildWide(catalog) : _buildNarrow(catalog),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- desktop
  Widget _buildWide(List<Product> catalog) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildMetaPanel(),
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          flex: 8,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildItemsHeader(),
                const SizedBox(height: 12),
                _buildItemsTable(catalog),
                const SizedBox(height: 16),
                _buildTotalsBar(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- mobile
  Widget _buildNarrow(List<Product> catalog) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMetaPanel(),
          const SizedBox(height: 24),
          _buildItemsHeader(),
          const SizedBox(height: 12),
          _buildMobileItems(catalog),
          const SizedBox(height: 16),
          _buildTotalsBar(),
        ],
      ),
    );
  }

  Widget _buildMetaPanel() {
    var suppliers =
        ref.watch(suppliersProvider).valueOrNull ?? const <Supplier>[];
    // A brand-new supplier just created from the dialog may not be in the
    // (still refreshing) list; include it so the dropdown never asserts.
    if (_supplierId != null && _pendingSupplierName != null) {
      final all = List<Supplier>.of(suppliers);
      if (!all.any((s) => s.id == _supplierId)) {
        all.add(Supplier(id: _supplierId!, name: _pendingSupplierName!));
      }
      suppliers = all;
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
              icon: Icons.receipt_long, title: 'INVOICE DETAILS'),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('invoiceNo'),
            controller: _invoiceNo,
            enabled: !_viewOnly,
            decoration: const InputDecoration(
              labelText: 'Invoice / GRN number *',
              prefixIcon: Icon(Icons.tag),
              isDense: true,
            ),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('supplierField'),
            value: _supplierId,
            items: [
              for (final s in suppliers)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            decoration: const InputDecoration(
              labelText: 'Supplier',
              prefixIcon: Icon(Icons.local_shipping_outlined),
              isDense: true,
            ),
            hint: const Text('Select a supplier'),
            onChanged: _viewOnly
                ? null
                : (value) => setState(() => _supplierId = value),
            validator: (_) => null,
          ),
          if (!_viewOnly) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _newSupplier,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New supplier'),
              ),
            ),
          ],
          const SizedBox(height: 4),
          TextFormField(
            key: const ValueKey('invoiceDate'),
            controller: _dateController,
            enabled: !_viewOnly,
            readOnly: true,
            onTap: _viewOnly
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) {
                      setState(() {
                        _date = picked;
                        _dateController.text = _formatDay(picked);
                      });
                    }
                  },
            decoration: const InputDecoration(
              labelText: 'Invoice date',
              prefixIcon: Icon(Icons.calendar_today_outlined),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('notes'),
            controller: _notes,
            enabled: !_viewOnly,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Payment terms, delivery reference…',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsHeader() {
    final count = _lineControllers.length;
    return Row(
      children: [
        Expanded(
          child: Text('ITEMS ($count)',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
        ),
        if (_viewOnly)
          const Text('Read only',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildItemsTable(List<Product> catalog) {
    final lines = _lineControllers.values.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lines.isNotEmpty)
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                horizontalMargin: 16,
                columns: const [
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Qty'), numeric: true),
                  DataColumn(label: Text('Unit Cost'), numeric: true),
                  DataColumn(label: Text('Amount'), numeric: true),
                  DataColumn(label: Text('Batch #')),
                  DataColumn(label: Text('Expiry')),
                  DataColumn(label: Text('')),
                ],
                rows: [
                  for (final line in lines)
                    DataRow(
                      cells: [
                        DataCell(SizedBox(
                          width: 240,
                          child: Text(line.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        )),
                        DataCell(SizedBox(
                          width: 90,
                          child: TextFormField(
                            key: ValueKey('lineQty-${line.id}'),
                            controller: line.qtyController,
                            enabled: !_viewOnly,
                            textAlign: TextAlign.end,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: _denseDeco(),
                            onChanged: (_) => setState(() {}),
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 120,
                          child: TextFormField(
                            key: ValueKey('lineCost-${line.id}'),
                            controller: line.costController,
                            enabled: !_viewOnly,
                            textAlign: TextAlign.end,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'))
                            ],
                            decoration: _denseDeco(),
                            onChanged: (_) => setState(() {}),
                          ),
                        )),
                        DataCell(Text(Money(line.amountPesewas).format(),
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(Text(line.batchNumber ?? '—')),
                        DataCell(Text(line.expiryDate == null
                            ? '—'
                            : _formatDay(line.expiryDate!))),
                        DataCell(IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Remove item',
                          onPressed: _viewOnly
                              ? null
                              : () => _removeLine(line.id),
                        )),
                      ],
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (!_viewOnly) _buildAddRow(catalog),
        if (lines.isEmpty && _viewOnly)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('No items on this invoice.',
                style: TextStyle(color: Colors.grey)),
          ),
      ],
    );
  }

  Widget _buildMobileItems(List<Product> catalog) {
    final lines = _lineControllers.values.toList();
    return Column(
      children: [
        for (final line in lines)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(line.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed:
                            _viewOnly ? null : () => _removeLine(line.id),
                      ),
                    ],
                  ),
                  if (line.batchNumber != null || line.expiryDate != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${line.batchNumber ?? 'No batch'} · ${line.expiryDate == null ? 'No expiry' : _formatDay(line.expiryDate!)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('lineQty-${line.id}'),
                          controller: line.qtyController,
                          enabled: !_viewOnly,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: const InputDecoration(
                              labelText: 'Qty', isDense: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          key: ValueKey('lineCost-${line.id}'),
                          controller: line.costController,
                          enabled: !_viewOnly,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}'))
                          ],
                          decoration: const InputDecoration(
                              labelText: 'Unit cost (₵)', isDense: true),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(Money(line.amountPesewas).format(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (!_viewOnly) _buildAddRow(catalog),
      ],
    );
  }

  Widget _buildAddRow(List<Product> catalog) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 820;
            final productField = ProductSearchField(
              controller: _productController,
              focusNode: _productFocusNode,
              catalog: catalog,
              onSelected: (product) => _onProductPicked(product),
              hintText: 'Type or tap a product…',
            );
            final qty = SizedBox(
              width: horizontal ? 110 : double.infinity,
              child: TextFormField(
                key: const ValueKey('addQty'),
                controller: _newQtyController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'Qty', isDense: true, prefixIcon: Icon(Icons.shopping_bag_outlined)),
              ),
            );
            final cost = SizedBox(
              width: horizontal ? 130 : double.infinity,
              child: TextFormField(
                key: const ValueKey('addCost'),
                controller: _newCostController,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
                ],
                decoration: const InputDecoration(
                    labelText: 'Unit cost (₵)', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            );
            final batch = SizedBox(
              width: horizontal ? 140 : double.infinity,
              child: TextFormField(
                key: const ValueKey('addBatch'),
                controller: _newBatchController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Batch #', isDense: true),
              ),
            );
            final expiry = SizedBox(
              width: horizontal ? 170 : double.infinity,
              child: TextFormField(
                key: const ValueKey('addExpiry'),
                controller: _newExpiryController,
                readOnly: true,
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _newExpiryDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    setState(() {
                      _newExpiryDate = picked;
                      _newExpiryController.text = _formatDay(picked);
                    });
                  }
                },
                decoration: const InputDecoration(
                    labelText: 'Expiry', isDense: true, suffixIcon: Icon(Icons.calendar_today_outlined, size: 16)),
              ),
            );
            final addButton = IconButton.filledTonal(
              key: const ValueKey('addItemButton'),
              tooltip: 'Add item to invoice',
              icon: const Icon(Icons.add),
              onPressed: _addLine,
            );

            if (horizontal) {
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: productField),
                      const SizedBox(width: 8),
                      qty,
                      const SizedBox(width: 8),
                      cost,
                      addButton,
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      batch,
                      const SizedBox(width: 8),
                      Expanded(child: expiry),
                      const Spacer(),
                      Text(
                        _newAmountText,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                productField,
                const SizedBox(height: 8),
                qty,
                const SizedBox(height: 8),
                cost,
                const SizedBox(height: 8),
                batch,
                const SizedBox(height: 8),
                expiry,
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    key: const ValueKey('addItemButton'),
                    onPressed: _addLine,
                    icon: const Icon(Icons.add),
                    label: const Text('Add item'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTotalsBar() {
    var total = 0;
    for (final line in _lineControllers.values) {
      total += line.amountPesewas;
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const Text('TOTAL',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(width: 12),
        Text(Money(total).format(),
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: OtcmsTheme.seed)),
      ],
    );
  }

  // ------------------------------------------------------------------ io
  void _onProductPicked(Product product) {
    setState(() {
      _productController.text = product.name;
      _productController.selection =
          TextSelection.collapsed(offset: product.name.length);
      _productFocusNode.unfocus();
      // Prefill a smart unit cost from the catalog when the user hasn't
      // typed one yet.
      if (_newCostController.text.trim().isEmpty &&
          (product.costPricePesewas ?? 0) > 0) {
        _newCostController.text =
            Money(product.costPricePesewas!).formatPlain();
      }
    });
  }

  void _addLine() {
    final name = _productController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Type or pick a product name first.')));
      return;
    }
    final qty = int.tryParse(_newQtyController.text.trim());
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid quantity.')));
      return;
    }
    final cost = Money.tryParse(_newCostController.text);
    if (cost == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid unit cost.')));
      return;
    }

    setState(() {
      final id = Ids.newId('l');
      final productId = _selectedProductId;
      final line = _EditorLine(
        id: id,
        productId: productId,
        name: name,
        quantity: qty,
        costPricePesewas: cost.pesewas,
        batchNumber: _newBatchController.text.trim().isEmpty
            ? null
            : _newBatchController.text.trim(),
        expiryDate: _newExpiryDate,
      );
      _lineControllers[line.id] = line;
      _productController.clear();
      _newQtyController.text = '1';
      _newCostController.clear();
      _newBatchController.clear();
      _newExpiryController.clear();
      _newExpiryDate = null;
      _selectedProductId = null;
      _productFocusNode.requestFocus();
    });
  }

  String? _selectedProductId;
  DateTime? _newExpiryDate;

  String get _newAmountText {
    final cost = Money.tryParse(_newCostController.text)?.pesewas ?? 0;
    final qty = int.tryParse(_newQtyController.text.trim()) ?? 0;
    if (cost <= 0 || qty <= 0) return '';
    return Money(qty * cost).format();
  }

  void _removeLine(String id) {
    setState(() {
      final line = _lineControllers.remove(id);
      line?.qtyController.dispose();
      line?.costController.dispose();
    });
  }

  Future<void> _newSupplier() async {
    final created = await showDialog<Supplier>(
      context: context,
      builder: (_) => const _NewSupplierDialog(),
    );
    if (!mounted || created == null) return;
    ref.invalidate(suppliersProvider);
    setState(() {
      _supplierId = created.id;
      _pendingSupplierName = created.name;
    });
  }

  List<PurchaseDraftLine> _collectLines() {
    return [
      for (final line in _lineControllers.values)
        if (line.amountPesewas > 0)
          PurchaseDraftLine(
            productName: line.name,
            productId: line.productId,
            quantity: int.tryParse(line.qtyController.text.trim()) ?? 0,
            costPricePesewas:
                Money.tryParse(line.costController.text)?.pesewas ?? 0,
            batchNumber: line.batchNumber,
            expiryDate: line.expiryDate,
          ),
    ];
  }

  Future<void> _save({required bool draft}) async {
    if (!_formKey.currentState!.validate()) return;
    final lines = _collectLines();
    if (lines.isEmpty) {
      _showMessage('Add at least one item with a quantity and cost.');
      return;
    }
    if (!draft && _supplierId == null) {
      _showMessage('Select a supplier before receiving the goods.');
      return;
    }
    final invoiceNo = _invoiceNo.text.trim();
    if (invoiceNo.isEmpty) {
      _showMessage('Enter the invoice / GRN number.');
      return;
    }

    setState(() => _saving = true);
    try {
      final service = ref.read(purchaseServiceProvider);
      final purchase = draft
          ? await service.saveDraft(
              purchaseId: existing?.id,
              purchaseNumber: invoiceNo,
              supplierId: _supplierId,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              date: _date,
              lines: lines,
            )
          : await service.receive(
              purchaseId: existing?.id,
              purchaseNumber: invoiceNo,
              supplierId: _supplierId!,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              date: _date,
              lines: lines,
            );
      if (!mounted) return;
      Navigator.of(context).pop(
          PurchaseEditorResult(purchase: purchase, received: !draft));
    } catch (e) {
      if (mounted) _showMessage('Could not save invoice: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static InputDecoration _denseDeco() {
    return const InputDecoration(isDense: true, border: OutlineInputBorder());
  }

  static String _formatDay(DateTime date) {
    final d = date.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

extension on PurchaseStatus {
  String get label => switch (this) {
        PurchaseStatus.draft => 'Draft',
        PurchaseStatus.ordered => 'Ordered',
        PurchaseStatus.received => 'Received',
        PurchaseStatus.cancelled => 'Cancelled',
      };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final PurchaseStatus status;

  Color get _color => switch (status) {
        PurchaseStatus.draft => Colors.blueGrey,
        PurchaseStatus.ordered => OtcmsTheme.caution,
        PurchaseStatus.received => OtcmsTheme.safe,
        PurchaseStatus.cancelled => OtcmsTheme.danger,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withOpacity(0.4)),
      ),
      child: Text(status.label.toUpperCase(),
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: _color)),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: OtcmsTheme.seed),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
      ],
    );
  }
}

class _NewSupplierDialog extends ConsumerStatefulWidget {
  const _NewSupplierDialog();

  @override
  ConsumerState<_NewSupplierDialog> createState() => _NewSupplierDialogState();
}

class _NewSupplierDialogState extends ConsumerState<_NewSupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController();
  late final _phone = TextEditingController();
  late final _email = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New supplier'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('supplierName'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Supplier name *', isDense: true),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('supplierPhone'),
                controller: _phone,
                decoration: const InputDecoration(
                    labelText: 'Phone', isDense: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('supplierEmail'),
                controller: _email,
                decoration: const InputDecoration(
                    labelText: 'Email', isDense: true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('saveSupplierButton'),
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final store = ref.read(localStoreProvider);
            final supplier = Supplier(
              id: Ids.supplierId(),
              name: _name.text.trim(),
              phone: _emptyToNull(_phone.text),
              email: _emptyToNull(_email.text),
              createdAt: DateTime.now().toUtc(),
            );
            await store.putSupplier(supplier);
            if (!mounted) return;
            Navigator.of(context).pop(supplier);
          },
          child: const Text('Save supplier'),
        ),
      ],
    );
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Suppliers for the invoice editor (sorted by name).
final suppliersProvider = FutureProvider<List<Supplier>>((ref) async {
  final store = ref.watch(localStoreProvider);
  final suppliers = await store.getSuppliers();
  suppliers.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return suppliers;
});