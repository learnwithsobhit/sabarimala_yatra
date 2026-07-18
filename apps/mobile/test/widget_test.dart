import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swamy_sharanam/app.dart';

void main() {
  testWidgets('App builds', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: SwamySharanamApp()));
    await tester.pump();
    expect(find.textContaining('Swamy'), findsWidgets);
  });
}
