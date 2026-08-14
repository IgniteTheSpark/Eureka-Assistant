import '../../api/api_client.dart';

/// Data access for account settings (§9 export / §10 deletion).
class AccountRepository {
  AccountRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  /// Lists exportable record types with counts (zero-count types hidden).
  Future<List<Map<String, dynamic>>> fetchExportOptions() async {
    final res = await _client.getJson('/api/account/export-options');
    final options = ((res as Map)['options'] as List?)?.cast<Map<String, dynamic>>();
    return options ?? const [];
  }

  /// Builds a Markdown or CSV export for the selected types.
  Future<String> exportData({
    required List<String> types,
    required String format, // 'md' | 'csv'
  }) async {
    return _client.postText('/api/account/export', {
      'types': types,
      'format': format,
    });
  }

  /// Permanently deletes the account (password re-authentication).
  Future<void> deleteAccount({required String password}) async {
    await _client.deleteWithBody('/api/account', {'password': password});
  }

  void close() => _client.close();
}
