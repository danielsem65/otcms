import 'package:flutter/material.dart';

import '../../models/product.dart';

/// Product picker with type-ahead suggestions from the catalog.
///
/// Typing shows matching products in a dropdown so long names can be picked
/// without typing them in full. The user may also type a brand-new name
/// (free text) — the editor then creates the product on save.
class ProductSearchField extends StatefulWidget {
  const ProductSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.catalog,
    required this.onSelected,
    this.hintText = 'Search or type a product name…',
    this.enabled = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<Product> catalog;
  final ValueChanged<Product> onSelected;
  final String hintText;
  final bool enabled;

  @override
  State<ProductSearchField> createState() => _ProductSearchFieldState();
}

class _ProductSearchFieldState extends State<ProductSearchField> {
  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Product>(
      textEditingController: widget.controller,
      focusNode: widget.focusNode,
      displayStringForOption: (p) => p.name,
      optionsBuilder: (textEditingValue) {
        final query = textEditingValue.text.trim().toLowerCase();
        if (query.isEmpty) return const Iterable<Product>.empty();
        final queryUpper = query.toUpperCase();
        return widget.catalog
            .where((p) => p.searchTokens.any((t) => t.contains(queryUpper)))
            .take(8);
      },
      onSelected: widget.onSelected,
      fieldViewBuilder:
          (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          key: const ValueKey('productSearchField'),
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            color: Theme.of(context).colorScheme.surface,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 460),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final product = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.medication_outlined, size: 18),
                    title: Text(product.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: product.genericName == null
                        ? null
                        : Text(product.genericName!,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      tooltip: 'Add ${product.name}',
                      onPressed: () => onSelected(product),
                    ),
                    onTap: () => onSelected(product),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}