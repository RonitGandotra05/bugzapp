import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'dart:io';
import '../models/bug_report.dart';
import '../models/user.dart';
import '../models/project.dart';
import '../models/comment.dart';
import '../constants/api_constants.dart';
import '../utils/token_storage.dart';
import '../services/logging_service.dart';

class BugReportService {
  final LoggingService _logger = LoggingService();
  
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

  // Get current user
  Future<User> getCurrentUser() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/users/me'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return User.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to get current user');
      }
    } catch (e, stackTrace) {
      _logger.error('Error getting current user', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get bug reports created by current user
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
        throw Exception('Failed to load created bug reports');
      }
    } catch (e, stackTrace) {
      _logger.error('Error loading created bug reports', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get bug reports assigned to current user
  Future<List<BugReport>> getAssignedBugReports(int userId) async {
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
        throw Exception('Failed to load assigned bug reports');
      }
    } catch (e, stackTrace) {
      _logger.error('Error loading assigned bug reports', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Toggle bug status
  Future<void> toggleBugStatus(int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/toggle_status'),
        headers: headers,
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to toggle bug status');
      }
    } catch (e, stackTrace) {
      _logger.error('Error toggling bug status', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Send reminder
  Future<Map<String, dynamic>> sendReminder(int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/$bugId/send_reminder'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        _logger.info('Reminder sent successfully for bug #$bugId');
        _logger.info('Notifications sent to: ${responseData['notifications_sent']}');
        
        if (responseData['failed_notifications']?.isNotEmpty ?? false) {
          _logger.warning('Some notifications failed: ${responseData['failed_notifications']}');
        }
        
        return responseData;
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Failed to send reminder';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error sending reminder for bug #$bugId', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Create bug report
  Future<void> createBugReport({
    required String description,
    required String recipientId,
    List<String> ccRecipients = const [],
    File? imageFile,
    String severity = 'low',
    String? projectId,
    String? tabUrl,
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
    } catch (e, stackTrace) {
      _logger.error('Error creating bug report', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Upload bug report with file
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
      _logger.info('Attempting to upload to URL: $url');
      
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

      if (imageFile != null) {
        _logger.info('Adding image file: ${imageFile.path}');
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
        _logger.info('Adding image bytes');
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
          },
        ),
      );

      if (response.data['message'] != 'Upload successful' || response.data['id'] == null) {
        throw Exception('Failed to upload bug report: ${response.data}');
      }
    } catch (e, stackTrace) {
      _logger.error('Error uploading bug report', error: e, stackTrace: stackTrace);
      if (e is DioException) {
        _logger.error('DioError details:', 
          error: {
            'request': e.requestOptions.uri,
            'headers': e.requestOptions.headers,
            'data': e.requestOptions.data,
            'response': e.response?.data,
          },
          stackTrace: stackTrace
        );
      }
      rethrow;
    }
  }

  // Get comments for a bug
  Future<List<Comment>> getBugComments(int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/$bugId/comments'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _logger.info('Retrieved ${data.length} comments for bug #$bugId');
        return data.map((json) => Comment.fromJson(json)).toList();
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Failed to load comments';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error getting comments for bug #$bugId', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Delete bug report
  Future<void> deleteBugReport(int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/$bugId'),
        headers: headers,
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to delete bug report');
      }
    } catch (e, stackTrace) {
      _logger.error('Error deleting bug report', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get projects
  Future<List<Project>> fetchProjects() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.projectsEndpoint}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Project.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load projects');
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching projects', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get all users
  Future<List<User>> fetchUsers() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.allUsersEndpoint}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => User.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load users');
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching users', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get all bug reports
  Future<List<BugReport>> getAllBugReports() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => BugReport.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load all bug reports');
      }
    } catch (e, stackTrace) {
      _logger.error('Error loading all bug reports', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get received bug reports (alias for getAssignedBugReports for backward compatibility)
  Future<List<BugReport>> getReceivedBugReports(int userId) async {
    return getAssignedBugReports(userId);
  }

  // Get image from S3
  Future<Uint8List?> getImage(String imageName) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/image/$imageName'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        _logger.warning('Failed to load image $imageName: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.error('Error loading image $imageName', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  // Get comments for a bug report
  Future<List<Comment>> getComments(int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/$bugId/comments'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _logger.info('Retrieved ${data.length} comments for bug #$bugId');
        return data.map((json) => Comment.fromJson(json)).toList();
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Failed to load comments';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error getting comments for bug #$bugId', error: e, stackTrace: stackTrace);
      return []; // Return empty list on error
    }
  }

  // Add a comment to a bug report
  Future<Comment> addComment(int bugId, String comment) async {
    try {
      _logger.info('Adding comment to bug #$bugId: $comment');
      
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/$bugId/comments'),
        headers: headers,
        body: json.encode({'comment': comment}),
      );

      _logger.info('Comment API response status: ${response.statusCode}');
      _logger.info('Comment API response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        return Comment.fromJson(data);
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Failed to add comment';
        _logger.error('Failed to add comment: $error');
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error adding comment to bug #$bugId', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
} 