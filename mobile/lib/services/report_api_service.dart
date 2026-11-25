import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';
import '../models/community_report.dart';

class ReportApiService {
  static Future<List<CommunityReport>> getReports({
    String? type,
    double? minLatitude,
    double? minLongitude,
    double? maxLatitude,
    double? maxLongitude,
  }) async {
    final query = <String, String>{
      'limit': '100',
      'offset': '0',
    };

    if (type != null && type != 'all') {
      query['type'] = type;
    }

    if (minLatitude != null &&
        minLongitude != null &&
        maxLatitude != null &&
        maxLongitude != null) {
      query['bbox'] = '$minLongitude,$minLatitude,$maxLongitude,$maxLatitude';
    }

    final uri = Uri.parse('${ApiConfig.baseUrl}/reports')
        .replace(queryParameters: query);

    final response = await http.get(uri).timeout(
          const Duration(seconds: 20),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Unable to load community reports (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body) as List<dynamic>;

    return decoded
        .map((item) => CommunityReport.fromJson(
              item as Map<String, dynamic>,
            ))
        .toList();
  }

  static Future<void> vote({
    required int reportId,
    required String vote,
  }) async {
    if (!AuthService.isLoggedIn) {
      throw Exception('Please log in to vote on reports.');
    }

    if (vote != 'confirm' && vote != 'clear') {
      throw Exception('Invalid vote type.');
    }

    final response = await http
        .post(
          Uri.parse('${ApiConfig.baseUrl}/reports/$reportId/$vote'),
          headers: AuthService.authenticatedHeaders,
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 401) {
      await AuthService.handleUnauthorized();
      throw Exception('Your session expired. Please log in again.');
    }

    if (response.statusCode != 200) {
      var message = 'Unable to submit vote (${response.statusCode}).';
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['detail'] is String) {
          message = data['detail'];
        }
      } catch (_) {}
      throw Exception(message);
    }
  }
}
