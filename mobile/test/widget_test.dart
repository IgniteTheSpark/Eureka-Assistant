import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eureka/main.dart';

void main() {
  testWidgets('app shell renders the dock + default surface', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: EurekaApp()));
    expect(find.text('Agent'), findsWidgets); // dock pill + chat header
    expect(find.text('流'), findsWidgets); // calendar segmented (default surface)
  });
}
