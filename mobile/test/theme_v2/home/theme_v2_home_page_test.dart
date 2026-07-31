import 'package:eureka/theme_v2/home/home_repository.dart';
import 'package:eureka/today/today_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fake repository returns supported Today data without Goal state', () async {
    const expected = TodayData.empty;
    final repository = _FakeHomeRepository(expected);

    expect(await repository.load(), same(expected));
  });
}

class _FakeHomeRepository implements ThemeV2HomeRepository {
  const _FakeHomeRepository(this.value);

  final TodayData value;

  @override
  Future<TodayData> load() async => value;
}
