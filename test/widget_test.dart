import 'package:flutter_test/flutter_test.dart';
import 'package:nareru/main.dart';

void main() {
  testWidgets('Nareru shows the weekly habit view', (tester) async {
    await tester.pumpWidget(const NareruApp());

    expect(find.text('This week'), findsWidgets);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Drink water'), findsOneWidget);
  });
}
