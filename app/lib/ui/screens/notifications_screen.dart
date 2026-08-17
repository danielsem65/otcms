import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/notification.dart';
import '../../state/dashboard_providers.dart';
import '../../state/providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(unreadNotificationsProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: notifications.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No notifications yet.\nExpiry and low-stock alerts appear here as your inventory moves.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final n in notifications)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        n.severity == NotificationSeverity.critical
                            ? Icons.error
                            : Icons.notifications_active,
                        color: n.severity == NotificationSeverity.critical
                            ? Colors.red
                            : Colors.orange,
                      ),
                      title: Text(n.title),
                      subtitle: Text(n.body ?? ''),
                    ),
                  ),
              ],
            ),
    );
  }
}