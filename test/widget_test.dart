import 'package:flutter_test/flutter_test.dart';
import 'package:novacut/main.dart';

void main() {
  testWidgets('NovaCut app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const NovaCutApp());

    expect(find.text('NovaCut'), findsOneWidget);
    expect(find.text('AI Tools'), findsOneWidget);
    expect(find.text('Export MP4'), findsOneWidget);
  });
}
