import 'package:flutter_test/flutter_test.dart';
import 'package:whami/app.dart';

void main() {
  testWidgets('WHAMI app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const WhamiApp());
    expect(find.byType(WhamiApp), findsOneWidget);
  });
}
