import '../../api/api_client.dart';
import '../../today/today_data.dart';

abstract interface class ThemeV2HomeRepository {
  Future<TodayData> load();
}

class ApiThemeV2HomeRepository implements ThemeV2HomeRepository {
  ApiThemeV2HomeRepository({ApiClient? api})
    : _api = api ?? ApiClient(),
      _ownsApi = api == null;

  final ApiClient _api;
  final bool _ownsApi;

  @override
  Future<TodayData> load() async {
    await _api.getJson('/ready');
    return loadToday(_api);
  }

  void dispose() {
    if (_ownsApi) _api.close();
  }
}
