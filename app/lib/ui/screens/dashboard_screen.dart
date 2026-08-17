import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../services/inventory_service.dart';
import '../../state/dashboard_providers.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// Professional pharmacy dashboard.
///
/// Every figure is computed from committed local data, so the dashboard
/// updates instantly after each local sale and works fully offline.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pharmacy = ref.watch(pharmacyProvider).valueOrNull;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final dashboard = ref.watch(dashboardProvider).valueOrNull ?? DashboardModel.empty;

    final symbol = settings?.currencySymbol ?? '₵';
    final expiredCount30 = (dashboard.expiryAlertCounts[ExpiryBucket.sevenDays] ?? 0) +
        (dashboard.expiryAlertCounts[ExpiryBucket.thirtyDays] ?? 0);
    final expiredCount90 = (dashboard.expiryAlertCounts[ExpiryBucket.sixtyDays] ?? 0) +
        (dashboard.expiryAlertCounts[ExpiryBucket.ninetyDays] ?? 0) +
        (dashboard.expiryAlertCounts[ExpiryBucket.oneEightyDays] ?? 0);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pharmacy?.name ?? 'OTCMS',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            if (pharmacy?.address != null && pharmacy!.address!.isNotEmpty)
              Text(pharmacy.address!,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(dashboardProvider),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(dashboardProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Today's sales
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: "TODAY'S SALES",
                    value: Money(dashboard.todaySalesPesewas).format(symbol: symbol),
                    icon: Icons.attach_money,
                    color: OtcmsTheme.seed,
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MetricCard(
                    title: 'TRANSACTIONS',
                    value: '${dashboard.todayTransactions}',
                    icon: Icons.receipt_long,
                    color: OtcmsTheme.seed,
                    onTap: () {},
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 700) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      title: 'UNITS SOLD',
                      value: '${dashboard.todayUnitsSold}',
                      icon: Icons.inventory,
                      color: OtcmsTheme.seed,
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      title: 'INVENTORY VALUE',
                      value: Money(dashboard.inventoryValuePesewas).format(symbol: symbol),
                      icon: Icons.warehouse,
                      color: OtcmsTheme.safe,
                      onTap: () {},
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            // Status chips
            if (MediaQuery.sizeOf(context).width >= 700)
              Row(
                children: [
                  _StatusChip(
                    label: 'PRODUCTS',
                    value: '${dashboard.productCount}',
                    color: OtcmsTheme.safe,
                  ),
                  _StatusChip(
                    label: 'LOW STOCK',
                    value: '${dashboard.lowStockCount}',
                    color: OtcmsTheme.warning,
                  ),
                  _StatusChip(
                    label: 'OUT OF STOCK',
                    value: '${dashboard.outOfStockCount}',
                    color: OtcmsTheme.danger,
                  ),
                  _StatusChip(
                    label: 'EXPIRING SOON',
                    value: '${dashboard.expiringSoonCount}',
                    color: OtcmsTheme.caution,
                  ),
                  _StatusChip(
                    label: 'EXPIRED',
                    value: '${dashboard.expiredCount}',
                    color: OtcmsTheme.danger,
                  ),
                ],
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(label: 'PRODUCTS', value: '${dashboard.productCount}', color: OtcmsTheme.safe),
                  _StatusChip(label: 'LOW STOCK', value: '${dashboard.lowStockCount}', color: OtcmsTheme.warning),
                  _StatusChip(label: 'OUT OF STOCK', value: '${dashboard.outOfStockCount}', color: OtcmsTheme.danger),
                  _StatusChip(label: 'EXPIRING SOON', value: '${dashboard.expiringSoonCount}', color: OtcmsTheme.caution),
                  _StatusChip(label: 'EXPIRED', value: '${dashboard.expiredCount}', color: OtcmsTheme.danger),
                ],
              ),
            const SizedBox(height: 16),
            // Products getting finished + expiry alerts
            if (MediaQuery.sizeOf(context).width >= 700)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Panel(
                      title: 'PRODUCTS GETTING FINISHED',
                      icon: Icons.trending_down,
                      child: dashboard.gettingFinished.isEmpty
                          ? const _EmptyHint('No products running low.')
                          : Column(
                              children: [
                                for (final (name, stock, critical) in dashboard.gettingFinished)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      critical ? Icons.error : Icons.warning_amber,
                                      color: critical ? OtcmsTheme.danger : OtcmsTheme.warning,
                                    ),
                                    title: Text(name,
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    trailing: Text('Stock: $stock',
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Panel(
                      title: 'EXPIRY ALERTS',
                      icon: Icons.event_busy,
                      child: Column(
                        children: [
                          _alertRow(context, dashboard.expiredCount, OtcmsTheme.danger, 'Expired'),
                          _alertRow(context, expiredCount30, OtcmsTheme.warning, 'Expiring within 30 days'),
                          _alertRow(context, expiredCount90, OtcmsTheme.caution, 'Expiring within 90 days'),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              _Panel(
                title: 'PRODUCTS GETTING FINISHED',
                icon: Icons.trending_down,
                child: dashboard.gettingFinished.isEmpty
                    ? const _EmptyHint('No products running low.')
                    : Column(
                        children: [
                          for (final (name, stock, critical) in dashboard.gettingFinished)
                            ListTile(
                              dense: true,
                              leading: Icon(
                                critical ? Icons.error : Icons.warning_amber,
                                color: critical ? OtcmsTheme.danger : OtcmsTheme.warning,
                              ),
                              title: Text(name,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Text('Stock: $stock',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              _Panel(
                title: 'EXPIRY ALERTS',
                icon: Icons.event_busy,
                child: Column(
                  children: [
                    _alertRow(context, dashboard.expiredCount, OtcmsTheme.danger, 'Expired'),
                    _alertRow(context, expiredCount30, OtcmsTheme.warning, 'Expiring within 30 days'),
                    _alertRow(context, expiredCount90, OtcmsTheme.caution, 'Expiring within 90 days'),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Top selling
            _Panel(
              title: 'TOP SELLING PRODUCTS TODAY',
              icon: Icons.emoji_events,
              child: dashboard.topSelling.isEmpty
                  ? const _EmptyHint('No sales yet today.')
                  : Column(
                      children: [
                        for (var i = 0; i < dashboard.topSelling.length; i++)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: OtcmsTheme.seed.withOpacity(0.12),
                              child: Text('${i + 1}',
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w700, color: OtcmsTheme.seed)),
                            ),
                            title: Text(dashboard.topSelling[i].$1,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Text('${dashboard.topSelling[i].$2} units'),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Helpers kept in this file to stay readable.
Widget _alertRow(BuildContext context, int count, Color color, String label) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
        Text('$count', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                  Text(title,
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: Colors.grey[600])),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: OtcmsTheme.moneyFontWeight,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: ',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700])),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: OtcmsTheme.seed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(text, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
    );
  }
}