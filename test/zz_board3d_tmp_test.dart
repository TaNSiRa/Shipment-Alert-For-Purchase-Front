
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchase_shipment_alert/main.dart';

// Temporary: renders the workflow board at several widths to PNG files.
const _steps = [
  ('Issue PO', 'N1', 'N1 — the PO date'),
  ('Acknowledgement (from supplier)', 'N2', 'N1 + 15 days'),
  ('OCR Acknowledgement to SAP', '', 'Same day as N2'),
  ('Shipping Instruction (from supplier)', 'N3', 'N2 + material lead time (default +40)'),
  ('OCR Shipping Instruction to SAP', '', 'Same day as N3'),
  ('Shipping documents from supplier (Invoice + P/L + B/L)', 'N4', 'N3 + 10 days'),
  ('Customs clearing & delivery to TP', 'N5', 'N4 + 7 days'),
  ('Input Declaration', '', 'N5 + 1 days'),
  ('Factory goods received', '', 'N5 + 2 days'),
];

void main() {
  for (final w in [620.0, 760.0, 956.0, 1300.0]) {
    testWidgets('board at $w', (tester) async {
      final key = GlobalKey();
      tester.view.physicalSize = Size(w + 40, 900);
      tester.view.devicePixelRatio = 1;
      var fallback = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: key,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(20),
                child: Board3dRail(
                  minCellPx: 140,
                  maxPerRow: 5,
                  minWidth: 520,
                  fallback: (_) {
                    fallback = true;
                    return const Text('FALLBACK');
                  },
                  stages: [
                    for (var i = 0; i < _steps.length; i++)
                      Board3dStage(
                        title: _steps[i].$1,
                        icon: Icons.circle_outlined,
                        accent: board3dPalette[i % board3dPalette.length],
                        number: '${i + 1}',
                        top: _steps[i].$2.isEmpty ? null : _steps[i].$2,
                        pills: [if (i == 3) ('ABSORBS LEAD TIME', Colors.indigo)],
                        lines: [_steps[i].$3],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(seconds: 5));
      final h = tester.getSize(find.byKey(key)).height;
      // ignore: avoid_print
      print('w=$w fallback=$fallback height=$h');
      tester.view.reset();
    });
  }
}
