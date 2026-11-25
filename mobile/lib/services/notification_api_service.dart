import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';

class NotificationApiService {
  NotificationApiService._();

  static Future<Map<String, dynamic>> getNotifications({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await http
        .get(
          Uri.parse(
            '${ApiConfig.baseUrl}/notifications?limit=$limit&offset=$offset',
          ),
          headers: AuthService.authenticatedHeaders,
        )
        .timeout(const Duration(seconds: 30));

    return _handleResponse(response);
  }

  static Future<void> markAsRead(int notificationId) async {
    final response = await http
        .patch(
          Uri.parse(
            '${ApiConfig.baseUrl}/notifications/$notificationId/read',
          ),
          headers: AuthService.authenticatedHeaders,
        )
        .timeout(const Duration(seconds: 30));

    _handleResponse(response);
  }

  static Future<void> markAllAsRead() async {
    final response = await http
        .patch(
          Uri.parse('${ApiConfig.baseUrl}/notifications/read-all'),
          headers: AuthService.authenticatedHeaders,
        )
        .timeout(const Duration(seconds: 30));

    _handleResponse(response);
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode == 401) {
      AuthService.handleUnauthorized();
      throw Exception('Session expired. Please log in again.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Notification request failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid notification response.');
    }

    return decoded;
  }
}
