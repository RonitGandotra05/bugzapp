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
  
  // Cache for comments
  static final Map<int, List<Comment>> _commentsCache = {};
  static final Map<int, DateTime> _commentsCacheTimestamp = {};
  
  // Cache duration (5 minutes)
  static const cacheDuration = Duration(minutes: 5);

  // Cache for users
  static List<User>? _usersCache;
  static DateTime? _usersCacheTimestamp;
  static const usersCacheDuration = Duration(minutes: 5);

  // Cache for projects
  static List<Project>? _projectsCache;
  static DateTime? _projectsCacheTimestamp;
  static const projectsCacheDuration = Duration(minutes: 5);

  // Cache for projects and their bug reports
  static final Map<int, List<BugReport>> _projectBugReportsCache = {};
  static final Map<int, DateTime> _projectBugReportsCacheTimestamp = {};
  static const _projectBugReportsCacheDuration = Duration(minutes: 5);

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
  Future<List<Project>> fetchProjects({bool fromCache = true}) async {
    final now = DateTime.now();
    
    // Return cached projects if available and not expired
    if (fromCache && _projectsCache != null && 
        _projectsCacheTimestamp != null && 
        now.difference(_projectsCacheTimestamp!) < projectsCacheDuration) {
      return _projectsCache!;
    }

    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/projects'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final projects = data.map((json) => Project.fromJson(json)).toList();
        
        // Update cache
        _projectsCache = projects;
        _projectsCacheTimestamp = now;
        
        return projects;
      } else {
        throw Exception('Failed to load projects');
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching projects', error: e, stackTrace: stackTrace);
      return _projectsCache ?? []; // Return cached projects on error if available
    }
  }

  // Get all users with caching
  Future<List<User>> fetchUsers() async {
    final now = DateTime.now();
    
    // Return cached users if available and not expired
    if (_usersCache != null && 
        _usersCacheTimestamp != null && 
        now.difference(_usersCacheTimestamp!) < usersCacheDuration) {
      return _usersCache!;
    }

    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.allUsersEndpoint}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final users = data.map((json) => User.fromJson(json)).toList();
        
        // Update cache
        _usersCache = users;
        _usersCacheTimestamp = now;
        
        return users;
      } else {
        throw Exception('Failed to load users');
      }
    } catch (e, stackTrace) {
      _logger.error('Error fetching users', error: e, stackTrace: stackTrace);
      return _usersCache ?? []; // Return cached users on error if available
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
    // Check cache first
    final cachedComments = _commentsCache[bugId];
    final cachedTimestamp = _commentsCacheTimestamp[bugId];
    final now = DateTime.now();

    if (cachedComments != null && 
        cachedTimestamp != null && 
        now.difference(cachedTimestamp) < cacheDuration) {
      return cachedComments;
    }

    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/$bugId/comments'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final comments = data.map((json) => Comment.fromJson(json)).toList();
        
        // Update cache
        _commentsCache[bugId] = comments;
        _commentsCacheTimestamp[bugId] = now;
        
        return comments;
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Failed to load comments';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error getting comments for bug #$bugId', error: e, stackTrace: stackTrace);
      return _commentsCache[bugId] ?? []; // Return cached comments on error if available
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

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        final newComment = Comment.fromJson(data);
        
        // Update cache
        _commentsCache[bugId] = [...(_commentsCache[bugId] ?? []), newComment];
        _commentsCacheTimestamp[bugId] = DateTime.now();
        
        return newComment;
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Failed to add comment';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error adding comment to bug #$bugId', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Clear cache for a specific bug
  void clearCommentsCache(int bugId) {
    _commentsCache.remove(bugId);
    _commentsCacheTimestamp.remove(bugId);
  }

  // Clear all cache
  void clearAllCache() {
    _commentsCache.clear();
    _commentsCacheTimestamp.clear();
  }

  // Add user registration
  Future<void> registerUser({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/users/register'),
        headers: headers,
        body: json.encode({
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
        }),
      );

      if (response.statusCode != 201) {
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
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('${ApiConstants.baseUrl}/users/$userId/toggle_admin'),
        headers: headers,
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
      final headers = await _getAuthHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/users/$userId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        // Clear users cache to force refresh
        _usersCache = null;
        _usersCacheTimestamp = null;
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Failed to delete user';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error deleting user', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Create project
  Future<Project> createProject({
    required String name,
    required String description,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/projects'),
        headers: headers,
        body: json.encode({
          'name': name,
          'description': description,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        final project = Project.fromJson(data);
        
        // Clear projects cache to force refresh
        _projectsCache = null;
        _projectsCacheTimestamp = null;
        
        return project;
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Failed to create project';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error creating project', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Delete project
  Future<void> deleteProject(int projectId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/projects/$projectId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        // Clear projects cache to force refresh
        _projectsCache = null;
        _projectsCacheTimestamp = null;
      } else {
        final error = json.decode(response.body)['detail'] ?? 'Failed to delete project';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error deleting project', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Add bug report to project
  Future<void> addBugReportToProject(int projectId, int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/projects/$projectId/bug_reports/$bugId'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        final error = json.decode(response.body)['detail'] ?? 'Failed to add bug report to project';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error adding bug report to project', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Remove bug report from project
  Future<void> removeBugReportFromProject(int projectId, int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConstants.baseUrl}/projects/$projectId/bug_reports/$bugId'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        final error = json.decode(response.body)['detail'] ?? 'Failed to remove bug report from project';
        throw Exception(error);
      }
    } catch (e, stackTrace) {
      _logger.error('Error removing bug report from project', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // Get bug reports in project
  Future<List<BugReport>> getBugReportsInProject(int projectId, {bool fromCache = true}) async {
    final now = DateTime.now();
    
    // Return cached bug reports if available and not expired
    if (fromCache && 
        _projectBugReportsCache.containsKey(projectId) && 
        _projectBugReportsCacheTimestamp.containsKey(projectId) &&
        now.difference(_projectBugReportsCacheTimestamp[projectId]!) < _projectBugReportsCacheDuration) {
      return _projectBugReportsCache[projectId]!;
    }

    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/projects/$projectId/bug_reports'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final bugReports = data.map((json) => BugReport.fromJson(json)).toList();
        
        // Update cache
        _projectBugReportsCache[projectId] = bugReports;
        _projectBugReportsCacheTimestamp[projectId] = now;
        
        return bugReports;
      } else {
        throw Exception('Failed to load bug reports for project');
      }
    } catch (e, stackTrace) {
      _logger.error('Error loading bug reports for project', error: e, stackTrace: stackTrace);
      return _projectBugReportsCache[projectId] ?? []; // Return cached bug reports on error if available
    }
  }
} 