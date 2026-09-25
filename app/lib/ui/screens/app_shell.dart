import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../sync/sync_engine.dart';
import '../theme.dart';
import 'batches_screen.dart';
import 'dashboard_screen.dart';
import 'expiry_screen.dart';
import 'inventory_screen.dart';
import 'notifications_screen.dart';
import 'products_screen.dart';
import 'purchases_screen.dart';
import 'reports_screen.dart';
import 'sales_screen.dart';
import 'settings_screen.dart';
import 'stock_count_screen.dart';
import 'suppliers_screen.dart';
import 'users_screen.dart';

/// App shell for desktop / laptop: left NavigationRail with the full menu
/// and a sync status bar pinned at the bottom.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _desktopIndex = 0;

  static const _destinations = <_Destination>[
    _Destination('Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard),
    _Destination('Sales', Icons.point_of_sale_outlined, Icons.point_of_sale),
    _Destination('Products', Icons.medication_outlined, Icons.medication),
    _Destination('Inventory', Icons.inventory_2_outlined, Icons.inventory_2),
    _Destination('Batches', Icons.layers_outlined, Icons.layers),
    _Destination('Expiry', Icons.event_busy_outlined, Icons.event_busy),
    _Destination('Purchases', Icons.shopping_cart_outlined, Icons.shopping_cart),
    _Destination('Suppliers', Icons.local_shipping_outlined, Icons.local_shipping),
    _Destination('Stock Count', Icons.fact_check_outlined, Icons.fact_check),
    _Destination('Reports', Icons.bar_chart_outlined, Icons.bar_chart),
    _Destination('Notifications', Icons.notifications_outlined, Icons.notifications),
    _Destination('Users', Icons.people_outline, Icons.people),
    _Destination('Settings', Icons.settings_outlined, Icons.settings),
  ];

  Widget _buildPage(int index) => switch (index) {
        0 => const DashboardScreen(),
        1 => const SalesScreen(),
        2 => const ProductsScreen(),
        3 => const InventoryScreen(),
        4 => const BatchesScreen(),
        5 => const ExpiryScreen(),
        6 => const PurchasesScreen(),
        7 => const SuppliersScreen(),
        8 => const StockCountScreen(),
        9 => const ReportsScreen(),
        10 => const NotificationsScreen(),
        11 => const UsersScreen(),
        12 => const SettingsScreen(),
        _ => const DashboardScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 80,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: OtcmsTheme.seed,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.local_pharmacy,
                            color: Colors.white, size: 20),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'OTCMS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1),
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (index, d) in _destinations.indexed)
                            _RailButton(
                              destination: d,
                              selected: index == _desktopIndex,
                              onTap: () =>
                                  setState(() => _desktopIndex = index),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _buildPage(_desktopIndex)),
        ],
      ),
      bottomNavigationBar: _SyncStatusBar(),
    );
  }
}

class _SyncStatusBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(syncStateStreamProvider).valueOrNull;
    final hasCloud = ref.watch(hasSupabaseProvider);
    final connectivity = ref.watch(connectivityProvider).status;

    final String label;
    final Color color;
    if (!hasCloud) {
      label = 'LOCAL MODE — DATA SAFE';
      color = OtcmsTheme.safe;
    } else if (event?.phase == SyncPhase.syncing) {
      label = 'SYNCING…';
      color = OtcmsTheme.caution;
    } else if (event?.phase == SyncPhase.error) {
      label = 'SYNC ERROR — LOCAL DATA SAFE';
      color = OtcmsTheme.warning;
    } else if (connectivity.isOnline) {
      label = 'ONLINE — SYNCED';
      color = OtcmsTheme.safe;
    } else {
      label = 'OFFLINE — WORKING LOCALLY';
      color = OtcmsTheme.warning;
    }

    return Material(
      color: color.withOpacity(0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(
              connectivity.isOnline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              ),
            ),
            if (event != null && event.pendingCount > 0)
              Text(
                '${event.pendingCount} CHANGES PENDING',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
              ),
          ],
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 30,
                decoration: BoxDecoration(
                  color: selected ? scheme.secondaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 20,
                  color: selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                destination.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
