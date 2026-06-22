import 'package:flutter_test/flutter_test.dart';
import 'package:eureka/today/next_action.dart';

void main() {
  group('fmtCountdown', () {
    test('under an hour → M 分 S 秒 (zero-padded)', () {
      expect(fmtCountdown(const Duration(minutes: 23)), '23 分 00 秒');
      expect(fmtCountdown(const Duration(minutes: 1, seconds: 5)), '01 分 05 秒');
      expect(fmtCountdown(const Duration(seconds: 9)), '00 分 09 秒');
    });
    test('≥ one hour → H 时 M 分', () {
      expect(fmtCountdown(const Duration(hours: 1, minutes: 5)), '1 时 05 分');
      expect(fmtCountdown(const Duration(hours: 2, seconds: 30)), '2 时 00 分');
    });
    test('negative clamps to zero', () {
      expect(fmtCountdown(const Duration(seconds: -10)), '00 分 00 秒');
    });
  });
}
