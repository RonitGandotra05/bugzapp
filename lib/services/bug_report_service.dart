import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import '../models/bug_report.dart';
import '../models/user.dart';
import '../models/project.dart';
import '../models/comment.dart';
import '../utils/token_storage.dart';
import '../constants/api_constants.dart';
import 'websocket_service.dart';
import 'auth_service.dart';

class BugReportService {
  static final BugReportService _instance = BugReportService._internal();
  factory BugReportService() => _instance;

  // Private fields
  final _cache = <String, dynamic>{};
  final _commentCache = <int, List<Comment>>{};
  final _cacheExpiry = <String, DateTime>{};
  final _cacheDuration = Duration(minutes: 5);
  final _client = http.Client();
  final _dio = Dio();
  bool _isLoadingData = false;
  bool _initialCommentsFetched = false;
  
  // WebSocket related fields
  late WebSocketService _webSocketService;
  final _bugReportController = StreamController<BugReport>.broadcast();
  final _commentController = StreamController<Comment>.broadcast();
  final _projectController = StreamController<Project>.broadcast();
  final _userController = StreamController<User>.broadcast();

  // Stream getters
  Stream<BugReport> get bugReportStream => _bugReportController.stream;
  Stream<Comment> get commentStream => _commentController.stream;
  Stream<Project> get projectStream => _projectController.stream;
  Stream<User> get userStream => _userController.stream;
  
  BugReportService._internal() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.sendTimeout = const Duration(seconds: 30);
  }

  // Initialize WebSocket after successful login
  Future<void> initializeWebSocket() async {
    final token = await TokenStorage.getToken();
    if (token != null) {
      final authService = AuthService();
      _webSocketService = WebSocketService(ApiConstants.baseUrl, authService);
      
      // Set up message handling before connecting
      _webSocketService.messageStream.listen((dynamic message) {
        try {
          if (message is String) {
            print('Received WebSocket message: $message');
            final data = jsonDecode(message);
            final type = data['type'];
            final payload = data['payload'];
            
            print('WebSocket message type: $type');
            
            switch (type) {
              case 'bug_report':
                final action = payload['event'];
                print('Handling bug report event: $action');
                _handleBugReportEvent(action, payload);
                break;
              case 'comment':
                print('Handling comment event');
                _handleCommentEvent(payload['event'], payload);
                break;
              case 'project':
                print('Handling project event');
                _handleProjectEvent(payload['event'], payload);
                break;
              case 'user':
                print('Handling user event');
                _handleUserEvent(payload['event'], payload);
                break;
              case 'system':
                print('System message: ${payload['message']}');
                break;
              case 'pong':
                print('Received pong from server: ${payload['timestamp']}');
                break;
              default:
                print('Unknown message type: $type');
            }
          }
        } catch (e, stackTrace) {
          print('Error processing WebSocket message: $e');
          print('Stack trace: $stackTrace');
          print('Original message: $message');
        }
      });
      
      await _webSocketService.connect();
      print('WebSocket connected successfully');
    } else {
      print('No token available for WebSocket connection');
    }
  }

  void _handleBugReportEvent(String action, Map<String, dynamic> payload) {
    try {
      print('Handling bug report event: $action with payload: $payload');
      
      // Extract the bug report data from the correct location in payload
      final bugReportData = Map<String, dynamic>.from(payload['bug_report'] ?? payload);
      print('Processing bug report data: $bugReportData');
      
      // Ensure we have the minimum required fields
      if (bugReportData['id'] == null) {
        print('Error: Bug report data missing ID');
        return;
      }
      
      // Add default values for required fields if they're missing
      bugReportData.putIfAbsent('modified_date', () => DateTime.now().toIso8601String());
      bugReportData.putIfAbsent('status', () => 'assigned');
      bugReportData.putIfAbsent('severity', () => 'low');
      bugReportData.putIfAbsent('description', () => 'No description');
      bugReportData.putIfAbsent('creator', () => 'Unknown');
      bugReportData.putIfAbsent('recipient', () => 'None');
      bugReportData.putIfAbsent('project_name', () => 'No Project');
      bugReportData.putIfAbsent('cc_recipients', () => []);
      
      print('Prepared bug report data: $bugReportData');
      
      final bugReport = BugReport.fromJson(bugReportData);
      print('Successfully parsed bug report: ${bugReport.id} - ${bugReport.description} - Created by: ${bugReport.creator}');
      
      switch (action) {
        case 'created':
          print('Received new bug report via WebSocket: ID ${bugReport.id}');
          _updateBugReportCache(bugReport);
          _bugReportController.add(bugReport);
          // Refresh the bug reports list to ensure we have the latest data
          getAllBugReports();
          break;
        case 'updated':
          print('Received bug report update via WebSocket: ID ${bugReport.id}');
          _updateBugReportCache(bugReport);
          _bugReportController.add(bugReport);
          break;
        case 'deleted':
          print('Received bug report deletion via WebSocket: ID ${bugReport.id}');
          _deleteBugReportFromCache(bugReport.id);
          _bugReportController.add(bugReport);
          break;
      }
    } catch (e, stackTrace) {
      print('Error handling bug report event: $e');
      print('Stack trace: $stackTrace');
      print('Original payload: $payload');
    }
  }

  void _handleCommentEvent(String action, Map<String, dynamic> payload) {
    try {
      final comment = Comment.fromJson(payload);
      
      switch (action) {
        case 'created':
          _addCommentToCache(comment);
          _commentController.add(comment);
          break;
        case 'updated':
          _updateCommentInCache(comment);
          _commentController.add(comment);
          break;
        case 'deleted':
          _deleteCommentFromCache(comment);
          _commentController.add(comment);
          break;
      }
    } catch (e) {
      print('Error handling comment event: $e');
    }
  }

  void _handleProjectEvent(String action, Map<String, dynamic> payload) {
    try {
      final project = Project.fromJson(payload);
      _projectController.add(project);
    } catch (e) {
      print('Error handling project event: $e');
    }
  }

  void _handleUserEvent(String action, Map<String, dynamic> payload) {
    try {
      final user = User.fromJson(payload);
      _userController.add(user);
    } catch (e) {
      print('Error handling user event: $e');
    }
  }

  // Cache management methods
  void _updateBugReportCache(BugReport bugReport) {
    final reports = (_cache['all_bug_reports'] as List<BugReport>? ?? []).toList();
    final index = reports.indexWhere((b) => b.id == bugReport.id);
    
    if (index != -1) {
      reports[index] = bugReport;
    } else {
      reports.add(bugReport);
    }
    
    // Sort by modified_date in descending order (most recent first)
    reports.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
    
    _cache['all_bug_reports'] = reports;
  }

  void _deleteBugReportFromCache(int bugId) {
    final reports = (_cache['all_bug_reports'] as List<BugReport>? ?? []).toList();
    reports.removeWhere((b) => b.id == bugId);
    _cache['all_bug_reports'] = reports;
    _commentCache.remove(bugId);
  }

  void _addCommentToCache(Comment comment) {
    if (!_commentCache.containsKey(comment.bugReportId)) {
      _commentCache[comment.bugReportId] = [];
    }
    _commentCache[comment.bugReportId]!.add(comment);
  }

  void _updateCommentInCache(Comment comment) {
    final comments = _commentCache[comment.bugReportId];
    if (comments != null) {
      final index = comments.indexWhere((c) => c.id == comment.id);
      if (index != -1) {
        comments[index] = comment;
      }
    }
  }

  void _deleteCommentFromCache(Comment comment) {
    final comments = _commentCache[comment.bugReportId];
    if (comments != null) {
      comments.removeWhere((c) => c.id == comment.id);
    }
  }

  void _clearUserRelatedCaches() {
    _cache.remove('users');
    _cache.remove('all_users');
    _cache.remove('current_user');
    _cache.remove('projects');
    _cache.remove('all_bug_reports');
    _cache.remove('created_bugs');
    _cache.remove('assigned_bugs');
    _commentCache.clear();
  }

  // Utility methods
  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await TokenStorage.getToken();
    if (token == null) {
      return {
        'Content-Type': 'application/json',
      };
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<T> _throttledRequest<T>(String cacheKey, Future<T> Function() request) async {
    if (_cache.containsKey(cacheKey) && 
        _cacheExpiry[cacheKey]!.isAfter(DateTime.now())) {
      return _cache[cacheKey] as T;
    }

    final result = await request();
    _cache[cacheKey] = result;
    _cacheExpiry[cacheKey] = DateTime.now().add(_cacheDuration);
    return result;
  }

  // Public API methods
  Future<List<BugReport>> getAllBugReports() async {
    return _throttledRequest('all_bug_reports', () async {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final reports = data.map((json) => BugReport.fromJson(json)).toList();
        
        // Sort by modified_date in descending order (most recent first)
        reports.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
        
        // Update cache with sorted data
        _cache['all_bug_reports'] = reports;
        
        return reports;
      }
      throw Exception('Failed to load bug reports');
    });
  }

  Future<List<Comment>> getComments(int bugId) async {
    if (!_commentCache.containsKey(bugId)) {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/comments'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _commentCache[bugId] = data.map((json) => Comment.fromJson(json)).toList();
      }
    }
    return _commentCache[bugId] ?? [];
  }

  List<Comment> getCachedComments(int bugId) {
    return _commentCache[bugId] ?? [];
  }

  Future<void> preloadComments(List<int> bugIds) async {
    for (final bugId in bugIds) {
      if (!_commentCache.containsKey(bugId)) {
        await getComments(bugId);
      }
    }
  }

  Future<void> addComment(int bugId, String comment) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/comments'),
      headers: await _getAuthHeaders(),
      body: jsonEncode({'comment': comment}),
    );

    if (response.statusCode == 201) {
      final commentData = Comment.fromJson(jsonDecode(response.body));
      _addCommentToCache(commentData);
      _commentController.add(commentData);
    } else {
      throw Exception('Failed to add comment');
    }
  }

  Future<Map<String, dynamic>> sendReminder(int bugId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/send_reminder'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        print('Reminder response: $responseData');
        return responseData;
      }
      
      // Handle error responses
      if (response.statusCode == 404) {
        throw Exception('Bug report not found');
      } else if (response.statusCode == 403) {
        throw Exception('Not authorized to send reminder');
      }
      
      // Try to get detailed error message from response
      try {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['detail'] ?? 'Failed to send reminder');
      } catch (_) {
        throw Exception('Failed to send reminder: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending reminder: $e');
      rethrow;
    }
  }

  Future<void> toggleAdminStatus(int userId) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}/users/$userId/toggle-admin'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to toggle admin status');
    }
  }

  Future<void> deleteUser(int userId) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}/users/$userId'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete user');
    }
  }

  Future<void> deleteProject(int projectId) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}/projects/$projectId'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete project');
    }
  }

  void clearCache() {
    _cache.clear();
    _commentCache.clear();
    _cacheExpiry.clear();
    _initialCommentsFetched = false;
  }

  void dispose() {
    _client.close();
    _webSocketService.dispose();
    _bugReportController.close();
    _commentController.close();
    _projectController.close();
    _userController.close();
  }

  // User Management Methods
  Future<User?> getCurrentUser() async {
    const cacheKey = 'current_user';
    
    // Clear cache if no token exists
    final token = await TokenStorage.getToken();
    if (token == null) {
      _cache.remove(cacheKey);
      return null;
    }
    
    if (_cache.containsKey(cacheKey) && 
        _cacheExpiry[cacheKey]!.isAfter(DateTime.now())) {
      final cachedUser = _cache[cacheKey] as User?;
      return cachedUser;
    }

    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/users/me'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final user = User.fromJson(jsonData);
        _cache[cacheKey] = user;
        _cacheExpiry[cacheKey] = DateTime.now().add(_cacheDuration);
        return user;
      }
      return null;
    } catch (e) {
      print('Error getting current user: $e');
      _cache.remove(cacheKey);
      return null;
    }
  }

  Future<List<User>> fetchUsers() async {
    return _throttledRequest('users', () async {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.allUsersEndpoint}'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => User.fromJson(json)).toList();
      }
      throw Exception('Failed to load users');
    });
  }

  Future<void> registerUser({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    try {
      final token = await TokenStorage.getToken();
      if (token == null) {
        throw Exception('Admin token required for registration');
      }

      final requestBody = Uri(queryParameters: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
      }).query;
      
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/register'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Bearer $token',
        },
        body: requestBody,
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        String errorMessage = 'Failed to register user';
        try {
          final errorJson = jsonDecode(response.body);
          if (errorJson['message'] != null) {
            errorMessage = errorJson['message'];
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }

      _clearUserRelatedCaches();
    } catch (e) {
      print('Registration error: $e');
      rethrow;
    }
  }

  // Bug Report Management Methods
  Future<void> uploadBugReport({
    required String description,
    required String recipientId,
    List<String>? ccRecipients,
    File? imageFile,
    Uint8List? imageBytes,
    String severity = 'low',
    String? projectId,
    String? tabUrl,
  }) async {
    final token = await TokenStorage.getToken();
    if (token == null) {
      throw Exception('No authentication token found');
    }

    // Ensure users are loaded in cache
    if (!_cache.containsKey('users')) {
      await fetchUsers();
    }

    // Get recipient name from users cache
    final users = _cache['users'] as List<User>;
    final recipientUser = users.firstWhere(
      (user) => user.id.toString() == recipientId,
      orElse: () => throw Exception('Recipient user not found'),
    );

    // Build form data with required fields
    final Map<String, dynamic> formFields = {
      'description': description,
      'recipient_name': recipientUser.name,
      'severity': severity,
    };

    // Add optional fields only if they have values
    if (projectId != null) {
      formFields['project_id'] = int.parse(projectId);
    }
    if (tabUrl != null && tabUrl.isNotEmpty) {
      formFields['tab_url'] = tabUrl;
    }

    final formData = FormData.fromMap(formFields);
    
    // Add file if provided (optional)
    if (imageFile != null) {
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

    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/upload',
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorDetail = response.data is Map ? response.data['detail'] : response.statusMessage;
        throw Exception('Failed to upload bug report: $errorDetail');
      }
    } catch (e) {
      print('Error uploading bug report: $e');
      rethrow;
    }
  }

  Future<void> toggleBugStatus(int bugId) async {
    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/toggle_status'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to toggle bug status');
    }

    _cache.remove('all_bug_reports');
    _cache.remove('created_bugs');
    _cache.remove('assigned_bugs');
  }

  Future<void> deleteBugReport(int bugId) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete bug report');
    }

    _cache.remove('all_bug_reports');
    _cache.remove('created_bugs');
    _cache.remove('assigned_bugs');
    _commentCache.remove(bugId);
  }

  // Project Management Methods
  Future<List<Project>> fetchProjects({bool fromCache = true}) async {
    return _throttledRequest('projects', () async {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.projectsEndpoint}'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => Project.fromJson(json)).toList();
      }
      throw Exception('Failed to load projects');
    });
  }

  Future<Project> createProject({
    required String name,
    required String description,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/projects'),
        headers: await _getAuthHeaders(),
        body: jsonEncode({
          'name': name,
          'description': description,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _cache.remove('projects');
        return Project.fromJson(jsonDecode(response.body));
      }
      
      throw Exception('Failed to create project');
    } catch (e) {
      print('Project creation error: $e');
      rethrow;
    }
  }

  // Comment Management Methods
  Future<void> loadAllComments() async {
    if (!_initialCommentsFetched) {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/all_comments'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        
        _commentCache.clear();
        for (var commentJson in data) {
          final comment = Comment.fromJson(commentJson);
          _addCommentToCache(comment);
        }
        
        _initialCommentsFetched = true;
      }
    }
  }
} 