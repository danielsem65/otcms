import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otcms/data/local/json/json_store.dart';
import 'package:otcms/main.dart' as app;
import 'package:otcms/state/providers.dart';

void main() {
  testWidgets('app boots and shows the dashboard in local mode', (tester) async {
    final store = JsonLocalStore(dataDirectory: 'otcms_test_widget');
    await tester.runAsync(() => store.open());

    await tester.pumpWidget(ProviderScope(
      overrides: [localStoreProvider.overrideWithValue(store)],
      child: const app.OtcmsApp(),
    ));
    await tester.pumpAndSettle();

    // Mobile shell shows the dashboard home + bottom navigation.
    expect(find.text('Agya Appiah OTCMS'), findsOneWidget);
    expect(find.text('Sell'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    // No Supabase configured in tests → local mode banner.
    expect(find.text('LOCAL MODE — DATA SAFE'), findsOneWidget);

    await tester.runAsync(() => store.close());
  });
}