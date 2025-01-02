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
import 'dart:async';
import 'dart:collection';

class BugReportService {
  static final BugReportService _instance = BugReportService._internal();
  factory BugReportService() => _instance;
  
  BugReportService._internal() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.sendTimeout = const Duration(seconds: 30);
  }

  final _cache = <String, dynamic>{};
  final _commentCache = <int, List<Comment>>{};
  final _cacheExpiry = <String, DateTime>{};
  final _cacheDuration = Duration(minutes: 5);
  final _client = http.Client();
  final _dio = Dio();
  bool _isLoadingData = false;
  
  // Track active requests with their completion status
  final _activeRequests = <_RequestTracker>[];
  static const _maxConcurrentRequests = 3;
  final _requestSemaphore = Semaphore(_maxConcurrentRequests);

  // Add a flag to track if initial fetch is done
  bool _initialCommentsFetched = false;

  Future<T> _throttledRequest<T>(String cacheKey, Future<T> Function() request) async {
    if (_cache.containsKey(cacheKey) && 
        _cacheExpiry[cacheKey]!.isAfter(DateTime.now())) {
      return _cache[cacheKey] as T;
    }

    return _requestSemaphore.run(() async {
      try {
        final future = request();
        final tracker = _RequestTracker(future);
        _activeRequests.add(tracker);
        final result = await future;
        _cache[cacheKey] = result;
        _cacheExpiry[cacheKey] = DateTime.now().add(_cacheDuration);
        return result;
      } catch (e) {
        print('Error in throttled request: $e');
        rethrow;
      } finally {
        _cleanupRequests();
      }
    });
  }

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

  Future<List<BugReport>> getAllBugReports() async {
    return _throttledRequest('all_bug_reports', () async {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => BugReport.fromJson(json)).toList();
      }
      throw Exception('Failed to load bug reports');
    });
  }

  Future<List<BugReport>> getCreatedBugReports(int userId) async {
    return _throttledRequest('created_bugs_$userId', () async {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.usersEndpoint}/$userId/created_bug_reports'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => BugReport.fromJson(json)).toList();
      }
      throw Exception('Failed to load created bug reports');
    });
  }

  Future<List<BugReport>> getAssignedBugReports(int userId) async {
    return _throttledRequest('assigned_bugs_$userId', () async {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.usersEndpoint}/$userId/received_bug_reports'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => BugReport.fromJson(json)).toList();
      }
      throw Exception('Failed to load assigned bug reports');
    });
  }

  Future<List<Comment>> getComments(int bugId) async {
    // Simply return from cache, no fetching
    return _commentCache[bugId] ?? [];
  }

  Future<void> loadAllComments() async {
    // This should be called once at login
    if (!_initialCommentsFetched) {
      await _fetchAllComments();
      _initialCommentsFetched = true;
    }
  }

  Future<void> _fetchAllComments() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/all_comments'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        
        // Clear existing cache
        _commentCache.clear();
        
        // Group comments by bug_report_id
        for (var commentJson in data) {
          final comment = Comment.fromJson(commentJson);
          if (!_commentCache.containsKey(comment.bugReportId)) {
            _commentCache[comment.bugReportId] = [];
          }
          _commentCache[comment.bugReportId]!.add(comment);
        }

        // Sort comments by created_at for each bug
        _commentCache.forEach((bugId, comments) {
          comments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
      }
    } catch (e) {
      print('Error fetching all comments: $e');
      rethrow;
    }
  }

  Future<Comment> addComment(int bugId, String comment) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/comments'),
      headers: await _getAuthHeaders(),
      body: jsonEncode({
        'comment': comment
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final newComment = Comment.fromJson(jsonDecode(response.body));
      
      // After adding a comment, refresh all comments to keep cache in sync
      await _fetchAllComments();
      
      return newComment;
    }
    throw Exception('Failed to add comment');
  }

  Future<void> toggleBugStatus(int bugId) async {
    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/toggle_status'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to toggle bug status');
    }

    // Invalidate relevant caches
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

    // Invalidate relevant caches
    _cache.remove('all_bug_reports');
    _cache.remove('created_bugs');
    _cache.remove('assigned_bugs');
    _commentCache.remove(bugId);
  }

  Future<Map<String, dynamic>> sendReminder(int bugId) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/send_reminder'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to send reminder');
  }

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

    print('Preparing to upload bug report with:');
    print('Description: $description');
    print('Recipient ID: $recipientId');
    print('CC Recipients: $ccRecipients');
    print('Severity: $severity');
    print('Project ID: $projectId');
    print('Tab URL: $tabUrl');

    // Get recipient name from ID
    final users = await fetchUsers();
    final recipient = users.firstWhere(
      (user) => user.id.toString() == recipientId,
      orElse: () => throw Exception('Recipient not found'),
    );

    final formData = FormData.fromMap({
      'description': description,
      'recipient_name': recipient.name,
      'cc_recipients': ccRecipients?.join(','),
      'severity': severity,
      'project_id': projectId,
      'tab_url': tabUrl,
    });

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

    try {
      print('Sending request to: ${ApiConstants.baseUrl}/upload');
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/upload',
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
          validateStatus: (status) {
            print('Received status code: $status');
            return status == 200 || status == 201;
          },
        ),
      );

      print('Response status code: ${response.statusCode}');
      print('Response data: ${response.data}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to upload bug report: ${response.statusMessage}');
      }
    } catch (e) {
      print('Error uploading bug report: $e');
      rethrow;
    }
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
      
      print('Registration request URL: ${ApiConstants.baseUrl}/register');
      print('Registration request body: $requestBody');
      print('Registration request headers: {Content-Type: application/x-www-form-urlencoded, Authorization: Bearer $token}');
      
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/register'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Bearer $token',
        },
        body: requestBody,
      );

      print('Registration response: ${response.body}');
      print('Registration status code: ${response.statusCode}');
      print('Registration headers: ${response.headers}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Clear all related caches
        _clearUserRelatedCaches();
        
        // Try to get success message from response
        try {
          final jsonResponse = jsonDecode(response.body);
          if (jsonResponse['message'] != null) {
            print('Registration success: ${jsonResponse['message']}');
          }
        } catch (_) {}
        return;
      }
      
      // Handle error cases
      String errorMessage = 'Failed to register user';
      try {
        final errorJson = jsonDecode(response.body);
        if (errorJson['message'] != null) {
          errorMessage = errorJson['message'];
        } else if (errorJson['detail'] != null) {
          errorMessage = errorJson['detail'];
        }
      } catch (_) {}
      
      throw Exception('$errorMessage (Status: ${response.statusCode})');
    } catch (e) {
      print('Registration error: $e');
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Failed to register user: $e');
    }
  }

  Future<void> toggleAdminStatus(int userId) async {
    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}/users/$userId/toggle_admin'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to toggle admin status');
    }

    // Clear all related caches
    _clearUserRelatedCaches();
  }

  Future<void> deleteUser(int userId) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}/users/$userId'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete user');
    }

    // Clear all related caches
    _clearUserRelatedCaches();
  }

  Future<Project> createProject({
    required String name,
    required String description,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/projects'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await TokenStorage.getToken()}',
        },
        body: jsonEncode({
          'name': name,
          'description': description,
        }),
      );

      print('Project creation response: ${response.body}');
      print('Project creation status code: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Clear project cache to force refresh
        _cache.remove('projects');
        return Project.fromJson(jsonDecode(response.body));
      }
      
      // Try to parse error message from response
      String errorMessage = 'Failed to create project';
      try {
        final errorJson = jsonDecode(response.body);
        if (errorJson['message'] != null) {
          errorMessage = errorJson['message'];
        } else if (errorJson['detail'] != null) {
          errorMessage = errorJson['detail'];
        }
      } catch (_) {}
      
      throw Exception('$errorMessage (Status: ${response.statusCode})');
    } catch (e) {
      print('Project creation error: $e');
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Failed to create project: $e');
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

    // Clear project cache to force refresh
    _cache.remove('projects');
  }

  Future<void> removeBugReportFromProject(int projectId, int bugId) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}/projects/$projectId/bug_reports/$bugId'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to remove bug report from project');
    }

    // Clear project and bug report caches since both are affected
    _cache.remove('projects');
    _cache.remove('all_bug_reports');
    _cache.remove('created_bugs');
    _cache.remove('assigned_bugs');
  }

  Future<void> preloadComments(List<int> bugIds) async {
    // No need to fetch, just ensure cache entries exist
    for (var bugId in bugIds) {
      _commentCache.putIfAbsent(bugId, () => []);
    }
  }

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

  void clearCache() {
    _cache.clear();
    _commentCache.clear();
    _cacheExpiry.clear();
    _activeRequests.clear();
    _initialCommentsFetched = false;  // Reset the flag when clearing cache
  }

  void dispose() {
    _client.close();
    clearCache();
    _cleanupRequests();
  }

  void _cleanupRequests() {
    _activeRequests.removeWhere((tracker) => tracker.isComplete);
  }

  // Helper method to clear all user-related caches
  void _clearUserRelatedCaches() {
    // Clear user caches
    _cache.remove('users');
    _cache.remove('all_users');
    _cache.remove('current_user');
    
    // Clear project caches since they might contain user info
    _cache.remove('projects');
    
    // Clear bug report caches since they contain user info
    _cache.remove('all_bug_reports');
    _cache.remove('created_bugs');
    _cache.remove('assigned_bugs');
    
    // Clear comment cache since it contains usernames
    _commentCache.clear();
  }
}

class Semaphore {
  final int maxCount;
  int _currentCount = 0;
  final _queue = Queue<Completer<void>>();

  Semaphore(this.maxCount);

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_currentCount < maxCount) {
      _currentCount++;
      return;
    }
    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
  }

  void _release() {
    if (_queue.isEmpty) {
      _currentCount--;
    } else {
      final completer = _queue.removeFirst();
      completer.complete();
    }
  }
}

// Helper class to track request completion
class _RequestTracker {
  final Future _future;
  bool isComplete = false;

  _RequestTracker(this._future) {
    _future.whenComplete(() => isComplete = true);
  }
} 