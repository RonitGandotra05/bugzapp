import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../models/bug_report.dart';
import '../models/comment.dart';
import '../utils/token_storage.dart';

class BugReportService {
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
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('Raw response: $data');
        return data.map((json) {
          try {
            return BugReport.fromJson(json);
          } catch (e) {
            print('Error parsing bug report: $e');
            print('Problematic JSON: $json');
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

  Future<void> createBugReport({
    required String description,
    required String imageUrl,
    required String tabUrl,
    required String mediaType,
    required String projectName,
    required String recipient,
    required String severity,
  }) async {
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
          'image_url': imageUrl,
          'tab_url': tabUrl,
          'media_type': mediaType,
          'project_name': projectName,
          'recipient': recipient,
          'severity': severity,
        }),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to create bug report: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<List<Map<String, dynamic>>> fetchProjects() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/projects'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((project) => {
          'id': project['id'] as int,
          'name': project['name'] as String,
        }).toList();
      } else {
        throw Exception('Failed to load projects: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<List<String>> fetchUsers() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/users'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<String>();
      } else {
        throw Exception('Failed to load users: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> uploadBugReport(Map<String, dynamic> formData) async {
    try {
      final token = await TokenStorage.getToken();
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseUrl}/upload'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      
      // Add all form fields
      formData.forEach((key, value) {
        if (value == null || (value is String && value.isEmpty)) return;
        
        if (value is http.MultipartFile) {
          request.files.add(value);
        } else {
          request.fields[key] = value.toString();
        }
      });

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('Upload response: ${response.body}');
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to upload: ${response.body}');
      }
    } catch (e) {
      print('Error in uploadBugReport: $e');
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<List<Comment>> getBugComments(int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/$bugId/comments'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Comment.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load comments: ${response.body}');
      }
    } catch (e) {
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
      throw Exception('Failed to connect to server: $e');
    }
  }
} 