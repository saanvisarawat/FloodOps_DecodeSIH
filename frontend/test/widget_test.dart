import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floodops_frontend/main.dart';

void main() {
  testWidgets('App boots to the guest dashboard with a visible SOS button', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FloodOpsApp()));
    await tester.pumpAndSettle();

    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('FloodOps Kerala'), findsOneWidget);
  });
}
