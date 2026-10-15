// The top bar's alerts menu. Run with: flutter test --platform chrome
// (the app is web-only). Debug-mode layout checks are what caught the bug
// this guards: the menu used to throw on every open.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchase_shipment_alert/main.dart';

void main() {
  Map<String, dynamic> po(int i) => {
        'id': i,
        'poNo': '19100004$i',
        'supplierShort': 'NIHON H/O',
        'currentStepName': 'Acknowledgement (from supplier)',
        'dueState': 'overdue',
        'overdueDays': 12,
        'status': 'ACTIVE',
      };

  Future<void> openBell(WidgetTester tester, List<dynamic> alerts, {void Function(Map<String, dynamic>)? onOpen}) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: AlertsBell(alerts: alerts, onOpen: onOpen ?? (_) {}, onSeeAll: () {}),
          ),
        ),
      ),
    ));
    await tester.tap(find.byTooltip('Alerts'));
    await tester.pumpAndSettle();
  }

  testWidgets('the alerts menu opens with alerts in it', (tester) async {
    Map<String, dynamic>? opened;
    await openBell(tester, [for (var i = 0; i < 30; i++) po(i)], onOpen: (p) => opened = p);
    expect(find.text('Needs attention'), findsOneWidget);
    await tester.tap(find.textContaining('PO 191000040').first);
    await tester.pumpAndSettle();
    expect(opened?['id'], 0);
  });

  testWidgets('the alerts menu opens when nothing needs attention', (tester) async {
    await openBell(tester, const []);
    expect(find.text('Nothing is overdue or due today'), findsOneWidget);
  });
}
