import 'dart:io';

import 'package:eureka/pet/floating_mascot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same peek outcome notifications keep an expanded nudge open', () {
    expect(
      shouldCollapseExpandedNudge(
        previousPeekId: 'n-1',
        nextPeekId: 'n-1',
        isNewArrival: false,
      ),
      isFalse,
    );
    expect(
      shouldCollapseExpandedNudge(
        previousPeekId: 'n-1',
        nextPeekId: null,
        isNewArrival: false,
      ),
      isTrue,
    );
    expect(
      shouldCollapseExpandedNudge(
        previousPeekId: 'n-1',
        nextPeekId: 'n-2',
        isNewArrival: true,
      ),
      isTrue,
    );
  });

  test('REKA long press is wired to voice release and slide cancellation', () {
    final source = File('lib/pet/floating_mascot.dart').readAsStringSync();

    expect(source, contains('onLongPressStart: _onLongPressStart'));
    expect(source, contains('onLongPressMoveUpdate: _onLongPressMoveUpdate'));
    expect(source, contains('onLongPressEnd: _onLongPressEnd'));
    expect(source, contains('onLongPressCancel: _onLongPressCancel'));
    expect(source, contains('details.offsetFromOrigin.dy'));
    expect(source, contains("ValueKey('reka-voice-bubble')"));
    expect(source, isNot(contains('_openLatestSession')));
  });
}
