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

/// Responsive app shell:
///  * Desktop (>= 1000px): NavigationRail + content pane.
///  * Mobile: bottom NavigationBar (Home, Sell, Products, Inventory, More).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _desktopIndex = 0;
  int _mobileIndex = 0;

  static const _desktopDestinations = <_Destination>[
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

  static const _mobileDestinations = <_Destination>[
    _Destination('Home', Icons.space_dashboard_outlined, Icons.space_dashboard),
    _Destination('Sell', Icons.point_of_sale_outlined, Icons.point_of_sale),
    _Destination('Products', Icons.medication_outlined, Icons.medication),
    _Destination('Inventory', Icons.inventory_2_outlined, Icons.inventory_2),
    _Destination('More', Icons.more_horiz, Icons.more_horiz),
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
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 1000;

    if (!isDesktop) {
      return Scaffold(
        body: _mobilePage(_mobileIndex),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _mobileIndex,
          onDestinationSelected: (i) => setState(() => _mobileIndex = i),
          destinations: [
            for (final d in _mobileDestinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.label,
              ),
          ],
        ),
      );
    }

    final pharmacy = ref.watch(pharmacyProvider).valueOrNull;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _desktopIndex,
            onDestinationSelected: (i) => setState(() => _desktopIndex = i),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 12),
              child: Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: OtcmsTheme.seed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.local_pharmacy, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'OTCMS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            destinations: [
              for (final d in _desktopDestinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: _buildPage(_desktopIndex)),
        ],
      ),
      bottomNavigationBar: _SyncStatusBar(),
    );
  }

  Widget _mobilePage(int index) {
    final content = switch (index) {
      0 => const DashboardScreen(),
      1 => const SalesScreen(),
      2 => const ProductsScreen(),
      3 => const InventoryScreen(),
      _ => const _MoreScreen(),
    };
    return Column(
      children: [
        _SyncStatusBar(),
        Expanded(child: content),
      ],
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

class _MoreScreen extends ConsumerWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = <(IconData, String, Widget)>[
      (Icons.layers_outlined, 'Batches', const BatchesScreen()),
      (Icons.event_busy_outlined, 'Expiry', const ExpiryScreen()),
      (Icons.shopping_cart_outlined, 'Purchases', const PurchasesScreen()),
      (Icons.local_shipping_outlined, 'Suppliers', const SuppliersScreen()),
      (Icons.fact_check_outlined, 'Stock Count', const StockCountScreen()),
      (Icons.bar_chart_outlined, 'Reports', const ReportsScreen()),
      (Icons.notifications_outlined, 'Notifications', const NotificationsScreen()),
      (Icons.people_outline, 'Users', const UsersScreen()),
      (Icons.settings_outlined, 'Settings', const SettingsScreen()),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (icon, label, screen) in items)
          Card(
            child: ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => screen,
                ));
              },
            ),
          ),
      ],
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
