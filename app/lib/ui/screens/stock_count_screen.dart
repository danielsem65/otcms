import 'package:flutter/material.dart';

/// Stock Count. Implemented in Phase 6.
class StockCountScreen extends StatelessWidget {
  const StockCountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _Placeholder(
      icon: Icons.fact_check,
      message: 'Physical stock counting with difference reasons. Lands in Phase 6.',
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon, required this.message});
  final IconData icon;
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
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
