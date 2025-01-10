import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../utils/token_storage.dart';
import '../services/bug_report_service.dart';

class AuthService {
  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.loginEndpoint}'),
        body: {
          'username': email,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        // Ensure user_id is properly handled
        if (responseData['user_id'] != null) {
          if (responseData['user_id'] is String) {
            responseData['user_id'] = int.tryParse(responseData['user_id']);
          }
        }
        
        return responseData;
      } else {
        final errorBody = json.decode(response.body);
        final errorMessage = errorBody['detail'] ?? errorBody['message'] ?? 'Invalid credentials';
        throw Exception(errorMessage);
      }
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> requestPasswordReset(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/forgot_password'),
        body: {
          'email': email,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to send OTP: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> resetPassword(String email, String otp, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/reset_password'),
        body: {
          'email': email,
          'otp': otp,
          'new_password': newPassword,
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to reset password: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<String?> getToken() async {
    return TokenStorage.getToken();
  }

  Future<void> logout() async {
    try {
      // Try to notify the server about logout
      final token = await TokenStorage.getToken();
      if (token != null) {
        try {
          await http.post(
            Uri.parse('${ApiConstants.baseUrl}/logout'),
            headers: {'Authorization': 'Bearer $token'},
          );
        } catch (e) {
          print('Error notifying server about logout: $e');
        }
      }
    } finally {
      // Always clear local data on explicit logout
      await TokenStorage.clearAll();
      BugReportService().clearCache();
    }
  }
} 