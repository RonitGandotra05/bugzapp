import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../constants/api_constants.dart';
import '../utils/token_storage.dart';
import '../services/logging_service.dart';

class UserService {
  final LoggingService _logger = LoggingService();

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await TokenStorage.getToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  // Get all users
  Future<List<User>> getAllUsers() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/all_users'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => User.fromJson(json)).toList();
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Failed to load users';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error loading users', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Register new user
  Future<void> registerUser({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}/register');
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(await _getAuthHeaders())
        ..fields.addAll({
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
        });

      final response = await http.Response.fromStream(await request.send());

      if (response.statusCode != 200) {
        final error = json.decode(response.body)['detail'] ?? 'Failed to register user';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error registering user', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Toggle admin status
  Future<void> toggleAdminStatus(int userId) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConstants.baseUrl}/users/$userId/toggle_admin'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode != 200) {
        final error = json.decode(response.body)['detail'] ?? 'Failed to toggle admin status';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error toggling admin status', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Delete user
  Future<void> deleteUser(int userId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/users/$userId'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode != 200) {
        final error = json.decode(response.body)['detail'] ?? 'Failed to delete user';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error deleting user', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
} 