import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:WHAMI/core/trust/trust_summary.dart';

void main() {
  testWidgets('layout smoke renders', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(800, 1200)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: Text('WHAMI layout smoke')),
        ),
      ),
    );
    expect(find.text('WHAMI layout smoke'), findsOneWidget);
  });

  test('TrustLevel short labels are plain language', () {
    expect(TrustLevel.reliable.shortLabel, 'Reliable');
    expect(TrustLevel.caution.shortLabel, 'Verify');
    expect(TrustLevel.unreliable.shortLabel, 'Unreliable');
  });
}
