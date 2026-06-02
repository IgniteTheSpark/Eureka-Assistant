import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eureka/main.dart';

void main() {
  testWidgets('app renders the Eureka title', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: EurekaApp()));
    expect(find.text('Eureka'), findsOneWidget);
  });
}
