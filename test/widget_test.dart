import 'package:flutter_test/flutter_test.dart';
import 'package:nareru/main.dart';

void main() {
  testWidgets('Nareru starts with no default habits', (tester) async {
    await tester.pumpWidget(const NareruApp());

    expect(find.text('This week'), findsWidgets);
    expect(find.text('Start with one small thing'), findsOneWidget);
    expect(find.text('Drink water'), findsNothing);
  });
}
