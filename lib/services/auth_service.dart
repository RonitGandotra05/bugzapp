import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../utils/token_storage.dart';

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
        return json.decode(response.body);
      } else {
        throw Exception('Failed to login: ${response.body}');
      }
    } catch (e) {
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

  Future<void> logout() async {
    try {
      // Clear all stored data
      await TokenStorage.clearAll();
      
      // Attempt to notify the server about logout
      final token = await TokenStorage.getToken();
      if (token != null) {
        try {
          await http.post(
            Uri.parse('${ApiConstants.baseUrl}/logout'),
            headers: {
              'Authorization': 'Bearer $token',
            },
          );
        } catch (e) {
          // Ignore server-side logout errors
          print('Server logout failed: $e');
        }
      }
    } catch (e) {
      throw Exception('Failed to logout: $e');
    }
  }
} 