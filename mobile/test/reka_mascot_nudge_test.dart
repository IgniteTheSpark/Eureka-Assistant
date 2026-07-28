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
}
