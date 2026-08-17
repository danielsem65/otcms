import 'package:flutter/material.dart';

/// Sales terminal — search/scan, cart, FEFO allocation, invoice.
/// Implemented in Phase 3 so it works fully offline.
class SalesScreen extends StatelessWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _PlaceholderScreen(
      icon: Icons.point_of_sale,
      title: 'Sales terminal (Phase 3)',
      message:
          'Search or scan a product, add a quantity, see the computed total, '
          'submit the sale and get the invoice immediately — even offline.',
    );
  }
}

/// Shared placeholder for screens that arrive in later phases.
class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: const Color(0xFF00897B).withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}