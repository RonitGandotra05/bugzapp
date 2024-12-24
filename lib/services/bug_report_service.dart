import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../models/bug_report.dart';
import '../models/comment.dart';
import '../utils/token_storage.dart';
import 'dart:io';
import '../models/user.dart';
import '../models/project.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

class BugReportService {
  // Add enum for severity levels
  static const Map<String, String> severityDisplayMap = {
    'high': 'High',
    'medium': 'Medium', 
    'low': 'Low'
  };

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await TokenStorage.getToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<List<BugReport>> getAllBugReports() async {
    try {
      final token = await TokenStorage.getToken();
      print('Using token: $token'); // Debug token

      final url = '${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}';
      print('Fetching from URL: $url'); // Debug URL

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      print('Response status code: ${response.statusCode}'); // Debug status
      print('Response headers: ${response.headers}'); // Debug headers
      print('Raw response body: ${response.body}'); // Debug body

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body) as List<dynamic>;
        print('Parsed data: $data');

        return data.map((item) {
          print('Processing item: $item'); // Debug each item
          if (item is! Map<String, dynamic>) {
            print('Invalid item format: $item');
            throw Exception('Invalid data format from server');
          }
          try {
            return BugReport.fromJson(item);
          } catch (e) {
            print('Error parsing bug report: $e');
            print('Problematic JSON: $item');
            rethrow;
          }
        }).toList();
      } else {
        throw Exception('Failed to load bug reports: ${response.body}');
      }
    } catch (e) {
      print('Error in getAllBugReports: $e');
      throw Exception('Error getting bug reports: $e');
    }
  }

  Future<List<BugReport>> getUserBugReports(int userId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/users/$userId/received_bug_reports'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => BugReport.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load user bug reports: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> toggleBugStatus(int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/toggle_status'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to toggle bug status: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> sendReminder(int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/send_reminder'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to send reminder: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> createBugReport(
    String description,
    String recipientId,
    List<String> ccRecipients,
    File? imageFile,
    String severity,
    String? projectId,
    String? tabUrl
  ) async {
    try {
      final token = await TokenStorage.getToken();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'description': description,
          'recipient_id': recipientId,
          'cc_recipients': ccRecipients,
          'image_file': imageFile,
          'severity': severity,
          'project_id': projectId,
          'tab_url': tabUrl,
        }),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to create bug report: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<List<Project>> fetchProjects() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.projectsEndpoint}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Project.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw Exception('Failed to load projects: ${response.body}');
      }
    } catch (e) {
      print('Error fetching projects: $e');
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<List<User>> fetchUsers() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.allUsersEndpoint}'),
        headers: headers,
      );

      print('Users API Response: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final users = data.map((json) => User.fromJson(json)).toList();
        print('Parsed Users: ${users.map((u) => '${u.name} (${u.id})')}');
        return users;
      } else {
        throw Exception('Failed to load users: ${response.body}');
      }
    } catch (e) {
      print('Error fetching users: $e');
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> uploadBugReport({
    required String description,
    required List<User> availableUsers,
    File? imageFile,
    Uint8List? imageBytes,
    String? recipientId,
    List<String> ccRecipients = const [],
    String severity = 'low',
    String? projectId,
    String? tabUrl,
  }) async {
    try {
      final token = await TokenStorage.getToken();
      final dio = Dio();
      dio.options.headers['Authorization'] = 'Bearer $token';
      
      final url = '${ApiConstants.baseUrl}/upload';
      print('Attempting to upload to URL: $url');
      
      // Get recipient name from available users
      final recipient = availableUsers.firstWhere(
        (user) => user.id.toString() == recipientId,
        orElse: () => throw Exception('Recipient not found'),
      );
      
      final formData = FormData.fromMap({
        'description': description,
        'recipient_name': recipient.name,
        'cc_recipients': ccRecipients.isEmpty ? null : ccRecipients.join(','),
        'severity': severity,
        'project_id': projectId != null ? int.parse(projectId) : null,
        'tab_url': tabUrl,
      });

      print('Form data fields: ${formData.fields}');

      if (imageFile != null) {
        print('Adding image file: ${imageFile.path}');
        formData.files.add(
          MapEntry(
            'file',
            await MultipartFile.fromFile(
              imageFile.path,
              filename: 'screenshot.png',
              contentType: MediaType('image', 'png'),
            ),
          ),
        );
      } else if (imageBytes != null) {
        print('Adding image bytes');
        formData.files.add(
          MapEntry(
            'file',
            MultipartFile.fromBytes(
              imageBytes,
              filename: 'screenshot.png',
              contentType: MediaType('image', 'png'),
            ),
          ),
        );
      }

      final response = await dio.post(
        url,
        data: formData,
        options: Options(
          validateStatus: (status) => status != null && (status >= 200 && status < 300),
          headers: {
            'Accept': '*/*',
            'Content-Type': 'multipart/form-data',
          },
        ),
      );

      print('Response status: ${response.statusCode}');
      print('Response data: ${response.data}');

      if (response.data['message'] == 'Upload successful' && response.data['id'] != null) {
        return;
      } else {
        throw Exception('Failed to create bug report: ${response.data}');
      }
    } catch (e) {
      print('Error uploading bug report: $e');
      if (e is DioException) {
        print('Request that failed: ${e.requestOptions.uri}');
        print('Request headers: ${e.requestOptions.headers}');
        print('Request data: ${e.requestOptions.data}');
        print('Response status: ${e.response?.statusCode}');
        print('Response data: ${e.response?.data}');
      }
      rethrow;
    }
  }

  Future<List<Comment>> getBugComments(int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/$bugId/comments'),
        headers: headers,
      );

      print('Comments response: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Comment.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load comments: ${response.body}');
      }
    } catch (e) {
      print('Error getting comments: $e');
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> addComment(int bugId, String comment) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/$bugId/comments'),
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'comment': comment,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to add comment: ${response.body}');
      }
    } catch (e) {
      print('Error adding comment: $e');
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> deleteBugReport(int bugId) async {
    try {
      final token = await TokenStorage.getToken();
      final dio = Dio();
      dio.options.headers['Authorization'] = 'Bearer $token';
      
      final url = '${ApiConstants.baseUrl}/bug_reports/$bugId';
      print('Attempting to delete bug report: $url');

      final response = await dio.delete(
        url,
        options: Options(
          validateStatus: (status) => status != null && (status >= 200 && status < 300),
          headers: {
            'Accept': '*/*',
          },
        ),
      );

      print('Response status: ${response.statusCode}');
      print('Response data: ${response.data}');

      if (response.statusCode != 200) {
        throw Exception('Failed to delete bug report: ${response.data}');
      }
    } catch (e) {
      print('Error deleting bug report: $e');
      if (e is DioException) {
        print('Request that failed: ${e.requestOptions.uri}');
        print('Request headers: ${e.requestOptions.headers}');
        print('Response status: ${e.response?.statusCode}');
        print('Response data: ${e.response?.data}');
      }
      rethrow;
    }
  }

  Future<List<BugReport>> getCreatedBugReports(int userId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/users/$userId/created_bug_reports'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => BugReport.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load created bug reports: ${response.body}');
      }
    } catch (e) {
      print('Error fetching created bug reports: $e');
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<List<BugReport>> getReceivedBugReports(int userId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/users/$userId/received_bug_reports'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => BugReport.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load received bug reports: ${response.body}');
      }
    } catch (e) {
      print('Error fetching received bug reports: $e');
      throw Exception('Failed to connect to server: $e');
    }
  }
} 