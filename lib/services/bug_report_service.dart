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
import 'dart:async';
import 'dart:collection';

class ApiConstants {
  static const String apiUrl = 'https://bugapi.tripxap.com';
}

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
    
    if (_cache.containsKey(cacheKey) && 
        _cacheExpiry[cacheKey]!.isAfter(DateTime.now())) {
      final cachedUser = _cache[cacheKey] as User?;
      print('Returning cached user: ${cachedUser?.toJson()}'); // Debug print
      return cachedUser;
    }

    final token = await TokenStorage.getToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.apiUrl}/users/me'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        print('Current user data from API: $jsonData'); // Debug print
        final user = User.fromJson(jsonData);
        print('Parsed user object: ${user.toJson()}'); // Debug print
        _cache[cacheKey] = user;
        _cacheExpiry[cacheKey] = DateTime.now().add(_cacheDuration);
        return user;
      }
      return null;
    } catch (e) {
      print('Error getting current user: $e');
      return null;
    }
  }

  Future<List<User>> fetchUsers() async {
    return _throttledRequest('users', () async {
      final response = await http.get(
        Uri.parse('${ApiConstants.apiUrl}/all_users'),
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
        Uri.parse('${ApiConstants.apiUrl}/projects'),
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
        Uri.parse('${ApiConstants.apiUrl}/bug_reports'),
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
        Uri.parse('${ApiConstants.apiUrl}/users/$userId/created_bug_reports'),
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
        Uri.parse('${ApiConstants.apiUrl}/users/$userId/received_bug_reports'),
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
    if (_commentCache.containsKey(bugId)) {
      return _commentCache[bugId]!;
    }

    return _throttledRequest('comments_$bugId', () async {
      final response = await http.get(
        Uri.parse('${ApiConstants.apiUrl}/bug_reports/$bugId/comments'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final comments = data.map((json) => Comment.fromJson(json)).toList();
        _commentCache[bugId] = comments;
        return comments;
      }
      throw Exception('Failed to load comments');
    });
  }

  Future<Comment> addComment(int bugId, String comment) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.apiUrl}/bug_reports/$bugId/comments'),
      headers: await _getAuthHeaders(),
      body: jsonEncode({'comment': comment}),
    );

    if (response.statusCode == 201) {
      final newComment = Comment.fromJson(jsonDecode(response.body));
      _commentCache[bugId]?.add(newComment);
      return newComment;
    }
    throw Exception('Failed to add comment');
  }

  Future<void> toggleBugStatus(int bugId) async {
    final response = await http.put(
      Uri.parse('${ApiConstants.apiUrl}/bug_reports/$bugId/toggle_status'),
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
      Uri.parse('${ApiConstants.apiUrl}/bug_reports/$bugId'),
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
      Uri.parse('${ApiConstants.apiUrl}/bug_reports/$bugId/send_reminder'),
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
      print('Sending request to: ${ApiConstants.apiUrl}/upload');
      final response = await _dio.post(
        '${ApiConstants.apiUrl}/upload',
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
    final response = await http.post(
      Uri.parse('${ApiConstants.apiUrl}/register'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
      },
    );

    if (response.statusCode != 201) {
      throw Exception('Failed to register user');
    }
  }

  Future<void> toggleAdminStatus(int userId) async {
    final response = await http.put(
      Uri.parse('${ApiConstants.apiUrl}/users/$userId/toggle_admin'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to toggle admin status');
    }
  }

  Future<void> deleteUser(int userId) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.apiUrl}/users/$userId'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete user');
    }
  }

  Future<Project> createProject({
    required String name,
    required String description,
  }) async {
    final response = await http.post(
      Uri.parse('${ApiConstants.apiUrl}/projects'),
      headers: await _getAuthHeaders(),
      body: jsonEncode({
        'name': name,
        'description': description,
      }),
    );

    if (response.statusCode == 201) {
      return Project.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to create project');
  }

  Future<void> deleteProject(int projectId) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.apiUrl}/projects/$projectId'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete project');
    }
  }

  Future<void> removeBugReportFromProject(int projectId, int bugId) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.apiUrl}/projects/$projectId/bug_reports/$bugId'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to remove bug report from project');
    }
  }

  Future<void> preloadComments(List<int> bugIds) async {
    final futures = bugIds.map((bugId) {
      if (_commentCache.containsKey(bugId)) {
        return Future.value(_commentCache[bugId]);
      }
      return Future.delayed(
        Duration(milliseconds: 200 * bugIds.indexOf(bugId)),
        () => getComments(bugId),
      );
    }).toList();

    try {
      await Future.wait(futures);
    } catch (e) {
      print('Error preloading comments: $e');
    }
  }

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await TokenStorage.getToken();
    if (token == null) {
      throw Exception('No authentication token found');
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
  }

  void dispose() {
    _client.close();
    _cleanupRequests();
  }

  void _cleanupRequests() {
    _activeRequests.removeWhere((tracker) => tracker.isComplete);
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