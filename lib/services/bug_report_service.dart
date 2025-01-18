import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart';
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
  final _client = http.Client();
  final _dio = Dio();
  bool _isLoadingData = false;
  bool _initialCommentsFetched = false;
  
  // Cache for bug reports
  List<BugReport>? _cachedBugReports;
  
  // Track recently added comments to prevent duplicates
  final _recentlyAddedComments = <int>{};
  final _recentlyAddedCommentsTimer = <int, Timer>{};
  
  // WebSocket related fields
  WebSocketService? _webSocketService;
  final _bugReportController = StreamController<BugReport>.broadcast();
  final _commentController = StreamController<Comment>.broadcast();
  final _projectController = StreamController<Project>.broadcast();
  final _userController = StreamController<User>.broadcast();
  Function()? _refreshCallback; // Add refresh callback
  bool _isRefreshing = false;

  BugReportService._internal() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.sendTimeout = const Duration(seconds: 30);
  }

  // Add method to set refresh callback
  void setRefreshCallback(Function() callback) {
    _refreshCallback = callback;
  }

  // Initialize WebSocket after successful login
  Future<void> initializeWebSocket() async {
    print('[BugReport Service] Starting WebSocket initialization...');
    try {
      final token = await TokenStorage.getToken();
      if (token == null) {
        print('[BugReport Service] No token available for WebSocket connection');
        return;
      }

      print('[BugReport Service] Token found, creating WebSocket service...');
      final authService = AuthService();
      _webSocketService = WebSocketService(
        ApiConstants.baseUrl, 
        authService,
        onRefreshNeeded: _refreshCallback, // Pass the refresh callback
      );
      
      // Listen to WebSocket messages
      _webSocketService!.messageStream.listen(
        (message) {
          print('[WebSocket] Raw message received: $message');
          if (message is String) {
            try {
              final data = jsonDecode(message);
              final type = data['type'];
              final payload = data['payload'];
              
              print('[WebSocket] Processing message of type: $type');
              
              switch (type) {
                case 'bug_report':
                  _handleBugReportEvent(payload);
                  break;
                case 'comment':
                  _handleCommentEvent(payload);
                  break;
                case 'project':
                  _handleProjectEvent(payload);
                  break;
                case 'user':
                  _handleUserEvent(payload);
                  break;
                case 'pong':
                  print('[WebSocket] Received pong response');
                  break;
                default:
                  print('[WebSocket] Unknown event type: $type');
              }
            } catch (e) {
              print('[WebSocket] Error processing message: $e');
            }
          }
        },
        onError: (error) {
          print('[WebSocket] Stream error: $error');
        },
        onDone: () {
          print('[WebSocket] Stream closed');
        },
      );

      print('[BugReport Service] Attempting WebSocket connection...');
      await _webSocketService!.connect();
      print('[BugReport Service] WebSocket connection initialized successfully');
    } catch (e) {
      print('[BugReport Service] Error initializing WebSocket: $e');
    }
  }

  void _handleBugReportEvent(Map<String, dynamic> payload) {
    try {
      final action = payload['event'];
      final bugReportData = payload['bug_report'];
      print('[WebSocket] Processing bug report event: $action');

      final bugReport = BugReport.fromJson(bugReportData);
      print('[WebSocket] Successfully parsed bug report #${bugReport.id}');

      // Update cache and notify listeners only if data has changed
      if (action == 'created' || action == 'updated') {
        BugReport? existingReport;
        try {
          existingReport = _cachedBugReports?.firstWhere(
            (b) => b.id == bugReport.id,
          );
        } catch (e) {
          // Report not found in cache
          existingReport = null;
        }
        
        final hasChanged = existingReport == null || 
            !_isBugReportEqual(existingReport, bugReport);
            
        if (hasChanged) {
          // Only update cache without triggering notification stream
          if (_cachedBugReports != null) {
            _cachedBugReports!.removeWhere((b) => b.id == bugReport.id);
            _cachedBugReports!.add(bugReport);
            _cachedBugReports!.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
          }
          print('[WebSocket] Updated bug report cache for #${bugReport.id} - data changed');
          
          // Only trigger notification for newly created bug reports
          if (action == 'created') {
            _bugReportController.add(bugReport);
            print('[WebSocket] Triggered notification for new bug report #${bugReport.id}');
          }
        } else {
          print('[WebSocket] Skipped bug report update for #${bugReport.id} - no changes');
        }
      } else if (action == 'deleted') {
        if (_cachedBugReports != null) {
          _cachedBugReports!.removeWhere((b) => b.id == bugReport.id);
          print('[WebSocket] Deleted bug report #${bugReport.id} from cache');
        }
      }
    } catch (e) {
      print('[WebSocket] Error processing bug report event: $e');
    }
  }

  bool _isBugReportEqual(BugReport a, BugReport b) {
    return a.id == b.id &&
           a.description == b.description &&
           a.status == b.status &&
           a.severity == b.severity &&
           a.recipientId == b.recipientId &&
           a.projectId == b.projectId &&
           a.modifiedDate == b.modifiedDate;
  }

  void _handleCommentEvent(Map<String, dynamic> payload) {
    try {
      final action = payload['event'];
      print('[WebSocket] Processing comment event: $action');

      final commentData = payload['data'];
      if (commentData == null) {
        print('[WebSocket] No comment data found in payload');
        return;
      }

      final comment = Comment.fromJson(commentData);
      print('[WebSocket] Created Comment object: id=${comment.id}, bugId=${comment.bugReportId}');

      if (action == 'comment_created') {
        // Check if comment already exists in cache
        final existingComments = _commentCache[comment.bugReportId] ?? [];
        final commentExists = existingComments.any((c) => c.id == comment.id);
        
        if (!commentExists) {
          // Add comment to cache
          if (!_commentCache.containsKey(comment.bugReportId)) {
            _commentCache[comment.bugReportId] = [];
          }
          _commentCache[comment.bugReportId]!.add(comment);
          _commentCache[comment.bugReportId]!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          
          // Only trigger notification for new comments
          _commentController.add(comment);
          print('[WebSocket] Added new comment to cache and triggered notification for bug #${comment.bugReportId}');
          
          // Update bug report comment count without triggering notification
          if (_cachedBugReports != null) {
            final bugReport = _cachedBugReports!.firstWhere(
              (b) => b.id == comment.bugReportId,
              orElse: () => throw Exception('Bug report not found'),
            );
            final updatedBugReport = BugReport.fromJson({
              ...bugReport.toJson(),
              'comment_count': (bugReport.commentCount + 1),
            });
            // Update cache without triggering notification
            _cachedBugReports!.removeWhere((b) => b.id == updatedBugReport.id);
            _cachedBugReports!.add(updatedBugReport);
            _cachedBugReports!.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
            print('[WebSocket] Updated bug report cache with new comment count');
          }
        } else {
          print('[WebSocket] Comment already exists in cache, skipping notification');
        }
      }
    } catch (e, stackTrace) {
      print('[WebSocket] Error processing comment event: $e');
      print('[WebSocket] Stack trace: $stackTrace');
    }
  }

  void _handleProjectEvent(Map<String, dynamic> payload) {
    try {
      final action = payload['event'];
      final projectData = payload['project'];
      print('[WebSocket] Processing project event: $action');

      final project = Project.fromJson(projectData);
      _projectController.add(project);
      print('[WebSocket] Processed project event for #${project.id}');
    } catch (e) {
      print('[WebSocket] Error processing project event: $e');
    }
  }

  void _handleUserEvent(Map<String, dynamic> payload) {
    try {
      final action = payload['event'];
      final userData = payload['user'];
      print('[WebSocket] Processing user event: $action');

      final user = User.fromJson(userData);
      _userController.add(user);
      print('[WebSocket] Processed user event for #${user.id}');
    } catch (e) {
      print('[WebSocket] Error processing user event: $e');
    }
  }

  // Stream getters
  Stream<BugReport> get bugReportStream => _bugReportController.stream;
  Stream<Comment> get commentStream => _commentController.stream;
  Stream<Project> get projectStream => _projectController.stream;
  Stream<User> get userStream => _userController.stream;

  // Public API methods
  Future<List<BugReport>> getAllBugReports() async {
    if (_cachedBugReports != null) {
      print('[BugReport Service] Using cached bug reports');
      return _cachedBugReports!;
    }

    try {
      final response = await _dio.get(
        '${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}',
        options: Options(
          headers: await _getAuthHeaders(),
        ),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        _cachedBugReports = data.map((json) => BugReport.fromJson(json)).toList();
        print('[BugReport Service] Fetched and cached ${_cachedBugReports!.length} bug reports');
        return _cachedBugReports!;
      } else {
        throw Exception('Failed to load bug reports');
      }
    } catch (e) {
      print('[BugReport Service] Error fetching bug reports: $e');
      rethrow;
    }
  }

  Future<List<BugReport>> getAllBugReportsNoCache() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final reports = data.map((json) => BugReport.fromJson(json)).toList();
        
        // Sort reports by modified date and ID
        reports.sort((a, b) {
          final dateComparison = b.modifiedDate.compareTo(a.modifiedDate);
          if (dateComparison != 0) return dateComparison;
          return b.id.compareTo(a.id);
        });
        
        // Update cache with fresh data
        _cachedBugReports = List<BugReport>.from(reports);
        print('[BugReport Service] Fetched and sorted ${reports.length} bug reports');
        if (reports.isNotEmpty) {
          print('[BugReport Service] First report: ID=${reports.first.id}, Date=${reports.first.modifiedDate}');
        }
        
        return reports;
      }
      throw Exception('Failed to load bug reports');
    } catch (e) {
      print('[BugReport Service] Error in getAllBugReportsNoCache: $e');
      rethrow;
    }
  }

  // Comment Management Methods
  Future<void> loadAllComments() async {
    try {
      final response = await _dio.get(
        '${ApiConstants.baseUrl}/all_comments',
        options: Options(headers: await _getAuthHeaders()),
      );

      if (response.statusCode == 200) {
        print('[BugReport Service] Received comments response');
        
        // Clear existing cache
        _commentCache.clear();
        
        // Process all comments
        final List<dynamic> commentsData = response.data;
        
        for (var commentJson in commentsData) {
          try {
            final comment = Comment(
              id: commentJson['id'],
              bugReportId: commentJson['bug_report_id'],
              userId: 0,
              userName: commentJson['user_name'],
              comment: commentJson['comment'],
              createdAt: DateTime.parse(commentJson['created_at']),
            );
            
            if (!_commentCache.containsKey(comment.bugReportId)) {
              _commentCache[comment.bugReportId] = [];
            }
            _commentCache[comment.bugReportId]!.add(comment);
            
            // Sort comments by creation date (newest first)
            _commentCache[comment.bugReportId]!.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          } catch (e) {
            print('[BugReport Service] Error processing comment: $e');
          }
        }
        
        _initialCommentsFetched = true;
        print('[BugReport Service] Successfully loaded and cached ${commentsData.length} comments');
      }
    } catch (e) {
      print('[BugReport Service] Error loading all comments: $e');
      rethrow;
    }
  }

  Future<List<Comment>> getComments(int bugId) async {
    if (!_initialCommentsFetched) {
      await loadAllComments();
    }
    final comments = _commentCache[bugId] ?? [];
    // Sort by created date, newest first
    comments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return comments;
  }

  List<Comment> getCachedComments(int bugId) {
    final comments = _commentCache[bugId] ?? [];
    // Sort by created date, newest first
    comments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return comments;
  }

  Future<void> preloadComments(List<int> bugIds) async {
    if (!_initialCommentsFetched) {
      await loadAllComments();
    }
  }

  Future<Comment> addComment(int bugReportId, String commentText) async {
    try {
      final response = await _dio.post(
        '${ApiConstants.baseUrl}/bug_reports/$bugReportId/comments',
        data: {'comment': commentText},
        options: Options(
          headers: await _getAuthHeaders(),
          validateStatus: (status) => status! < 500,
        ),
      );

      if (response.statusCode == 200) {
        // Only create the comment object but don't add to cache or stream
        // The WebSocket event will handle that
        return Comment(
          id: response.data['id'],
          bugReportId: response.data['bug_report_id'],
          userId: 0,
          userName: response.data['user_name'],
          comment: response.data['comment'],
          createdAt: DateTime.parse(response.data['created_at']),
        );
      }
      throw Exception('Failed to add comment: ${response.statusCode}');
    } catch (e) {
      print('[BugReport Service] Error adding comment: $e');
      rethrow;
    }
  }

  // Bug Report Management Methods
  Future<void> uploadBugReport({
    required String description,
    required String recipientName,
    File? imageFile,
    Uint8List? imageBytes,
    String severity = 'low',
    String? projectId,
    String? tabUrl,
    List<String> ccRecipients = const [],
  }) async {
    try {
      final dio = Dio();
      
      final token = await TokenStorage.getToken();
      dio.options.headers['Authorization'] = 'Bearer $token';

      final formData = FormData();
      formData.fields.addAll([
        MapEntry('description', description),
        MapEntry('recipient_name', recipientName),
        MapEntry('severity', severity),
        if (projectId != null) MapEntry('project_id', projectId),
        if (tabUrl != null) MapEntry('tab_url', tabUrl),
        if (ccRecipients.isNotEmpty) MapEntry('cc_recipients', ccRecipients.join(',')),
      ]);

      print('[BugReport Service] Uploading bug report with fields:');
      print('Description: $description');
      print('Recipient Name: $recipientName');
      print('Severity: $severity');
      print('Project ID: $projectId');
      print('Tab URL: $tabUrl');
      print('CC Recipients: ${ccRecipients.join(',')}');

      // Determine media type based on file extension and file type
      String? mediaType;
      String? contentType;
      String? fileName;
      
      if (imageFile != null) {
        final extension = path.extension(imageFile.path).toLowerCase();
        final mimeType = lookupMimeType(imageFile.path);
        print('[BugReport Service] File details - Path: ${imageFile.path}, Extension: $extension, Detected MIME: $mimeType');
        
        // Set media type and content type based on file type
        if (mimeType?.startsWith('video/') == true || 
            ['.mp4', '.mov', '.3gp'].contains(extension)) {
          mediaType = 'video';
          switch (extension) {
            case '.mp4':
              contentType = 'video/mp4';
              break;
            case '.mov':
              contentType = 'video/quicktime';
              break;
            case '.3gp':
              contentType = 'video/3gpp';
              break;
            default:
              contentType = mimeType ?? 'video/mp4';
          }
          fileName = 'video-${DateTime.now().millisecondsSinceEpoch}$extension';
        } else {
          mediaType = 'image';
          contentType = mimeType ?? 'image/png';
          fileName = 'image-${DateTime.now().millisecondsSinceEpoch}${extension.isNotEmpty ? extension : '.png'}';
        }

        print('[BugReport Service] File type detection - Media Type: $mediaType, Content Type: $contentType, Filename: $fileName');

        // Read file as bytes to ensure it's not empty
        final bytes = await imageFile.readAsBytes();
        if (bytes.isEmpty) {
          throw Exception('File is empty');
        }

        // Add file to form data
        formData.files.add(
          MapEntry(
            'file',
            MultipartFile.fromBytes(
              bytes,
              filename: fileName,
              contentType: MediaType.parse(contentType ?? 'application/octet-stream'),
            ),
          ),
        );

        // Add media type to form data
        formData.fields.add(MapEntry('media_type', mediaType ?? 'image'));
      } else if (imageBytes != null) {
        mediaType = 'image';
        contentType = 'image/png';
        fileName = 'image-${DateTime.now().millisecondsSinceEpoch}.png';

        formData.files.add(
          MapEntry(
            'file',
            MultipartFile.fromBytes(
              imageBytes,
              filename: fileName,
              contentType: MediaType.parse(contentType),
            ),
          ),
        );
        formData.fields.add(MapEntry('media_type', mediaType ?? 'image'));
      }

      final response = await dio.post(
        '${ApiConstants.baseUrl}/upload',
        data: formData,
        options: Options(
          validateStatus: (status) => status! < 500,
          headers: {
            'Accept': '*/*',
            'Content-Type': 'multipart/form-data',
          },
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('[BugReport Service] Upload successful: ${response.data}');
        // Clear the cache to force a refresh
        _cachedBugReports = null;
        _commentCache.clear();
      } else {
        print('[BugReport Service] Upload failed with status ${response.statusCode}: ${response.data}');
        throw Exception('Failed to upload bug report: ${response.statusCode}');
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
  }

  Future<void> deleteBugReport(int bugId) async {
    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete bug report');
    }

    deleteBugReportFromCache(bugId);
  }

  Future<Map<String, dynamic>> sendReminder(int bugId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/send_reminder'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('Failed to send reminder');
    } catch (e) {
      print('[BugReport Service] Error sending reminder: $e');
      rethrow;
    }
  }

  // User Management Methods
  Future<User?> getCurrentUser() async {
    try {
      final token = await TokenStorage.getToken();
      if (token == null) {
        print('[BugReport Service] No token found for getCurrentUser');
        return null;
      }

      final response = await _dio.get(
        '${ApiConstants.baseUrl}/users/me',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200) {
        return User.fromJson(response.data);
      }
      return null;
    } catch (e) {
      print('[BugReport Service] Error getting current user: $e');
      return null;
    }
  }

  Future<List<User>> fetchUsers() async {
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.allUsersEndpoint}'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => User.fromJson(json)).toList();
    }
    throw Exception('Failed to load users');
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

      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/register'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Bearer $token',
        },
        body: {
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
        },
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to register user');
      }
    } catch (e) {
      print('[BugReport Service] Registration error: $e');
      rethrow;
    }
  }

  Future<void> toggleAdminStatus(int userId) async {
    final response = await _dio.put(
      '${ApiConstants.baseUrl}/users/$userId/toggle_admin',
      options: Options(
        headers: await _getAuthHeaders(),
      ),
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

  // Project Management Methods
  Future<List<Project>> fetchProjects({bool fromCache = true}) async {
    if (fromCache && _cache.containsKey('projects')) {
      return _cache['projects'] as List<Project>;
    }

    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}${ApiConstants.projectsEndpoint}'),
      headers: await _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      final projects = data.map((json) => Project.fromJson(json)).toList();
      _cache['projects'] = projects;
      return projects;
    }
    throw Exception('Failed to load projects');
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
        invalidateProjectCache();
        return Project.fromJson(jsonDecode(response.body));
      }
      throw Exception('Failed to create project');
    } catch (e) {
      print('[BugReport Service] Project creation error: $e');
      rethrow;
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
    invalidateProjectCache();
  }

  // Cache Management Methods
  void clearCache() {
    _cache.clear();
    _commentCache.clear();
    _cachedBugReports = null;
    _initialCommentsFetched = false;
  }

  void addCommentToCache(Comment comment) {
    print('[BugReport Service] Adding comment to cache for bug #${comment.bugReportId}');
    
    // Add comment to cache
    final comments = _commentCache[comment.bugReportId] ?? [];
    comments.add(comment);
    _commentCache[comment.bugReportId] = comments;
    
    // Sort comments by creation date (newest first)
    comments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
    // Update bug report comment count without triggering notification
    final bugReport = _cachedBugReports?.firstWhere(
      (bug) => bug.id == comment.bugReportId,
      orElse: () => BugReport(
        id: comment.bugReportId,
        description: '',
        status: BugStatus.assigned,
        severity: SeverityLevel.low,
        modifiedDate: DateTime.now(),
      ),
    );
    
    if (bugReport != null) {
      final updatedBugReport = BugReport(
        id: bugReport.id,
        description: bugReport.description,
        imageUrl: bugReport.imageUrl,
        status: bugReport.status,
        severity: bugReport.severity,
        creator: bugReport.creator,
        recipient: bugReport.recipient,
        mediaType: bugReport.mediaType,
        modifiedDate: bugReport.modifiedDate,
        projectId: bugReport.projectId,
        projectName: bugReport.projectName,
        tabUrl: bugReport.tabUrl,
        ccRecipients: bugReport.ccRecipients,
        commentCount: comments.length,
      );
      
      // Update cache without triggering notification
      if (_cachedBugReports != null) {
        _cachedBugReports!.removeWhere((bug) => bug.id == updatedBugReport.id);
        _cachedBugReports!.add(updatedBugReport);
        _cachedBugReports!.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
      }
      print('[BugReport Service] Updated cache for bug report #${comment.bugReportId} with new comment count');
    }
    
    // Notify listeners about new comment only
    _commentController.add(comment);
  }

  void deleteBugReportFromCache(int bugId) {
    if (_cachedBugReports != null) {
      _cachedBugReports!.removeWhere((b) => b.id == bugId);
      print('[BugReport Service] Removed bug report #$bugId from cache');
    }
    // Clear associated comments
    _commentCache.remove(bugId);
  }

  void invalidateProjectCache() {
    print('[BugReport Service] Invalidating project cache');
    _cache.remove('projects');
  }

  void invalidateUserCache() {
    print('[BugReport Service] Invalidating user cache');
    _cache.remove('users');
  }

  void updateBugReportCache(BugReport bugReport) {
    print('[BugReport Service] Updating cache for bug report #${bugReport.id}');
    
    // Remove existing bug report if present
    _cachedBugReports?.removeWhere((bug) => bug.id == bugReport.id);
    
    // Add new bug report
    _cachedBugReports?.add(bugReport);
    
    // Sort bug reports by modified date (newest first)
    _cachedBugReports?.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));
    
    // Notify listeners
    _bugReportController.add(bugReport);
  }

  Future<void> refreshBugReports() async {
    await getAllBugReportsNoCache();
  }

  Future<void> refreshEverything() async {
    if (_isRefreshing) {
      print('[BugReport Service] Already refreshing, skipping');
      return;
    }

    _isRefreshing = true;
    print('[BugReport Service] Starting complete refresh of all data');

    try {
      // Clear all caches first
      print('[BugReport Service] Clearing all caches');
      _cache.clear();
      _commentCache.clear();
      _cachedBugReports = null;
      _initialCommentsFetched = false;

      // Fetch all data in parallel
      print('[BugReport Service] Fetching fresh data');
      await Future.wait<void>([
        getAllBugReportsNoCache().then((reports) {
          print('[BugReport Service] Refreshed ${reports.length} bug reports');
        }),
        loadAllComments().then((_) {
          print('[BugReport Service] Refreshed comments');
        }),
        fetchProjects(fromCache: false).then((projects) {
          print('[BugReport Service] Refreshed ${projects.length} projects');
        }),
        fetchUsers().then((users) {
          print('[BugReport Service] Refreshed ${users.length} users');
        }),
      ]);

      print('[BugReport Service] Complete refresh finished successfully');
    } catch (e) {
      print('[BugReport Service] Error during refresh: $e');
      // On error, invalidate all caches to ensure fresh data on next fetch
      _cache.clear();
      _commentCache.clear();
      _cachedBugReports = null;
      _initialCommentsFetched = false;
      rethrow;
    } finally {
      _isRefreshing = false;
    }
  }

  List<BugReport> getCachedBugReports() {
    return _cachedBugReports ?? [];
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

  void dispose() {
    _client.close();
    _webSocketService?.dispose();
    _bugReportController.close();
    _commentController.close();
    _projectController.close();
    _userController.close();
    // Cancel all timers
    for (var timer in _recentlyAddedCommentsTimer.values) {
      timer.cancel();
    }
    _recentlyAddedCommentsTimer.clear();
  }

  Future<void> createBugReport({
    required String description,
    required String recipientName,
    List<String> ccRecipients = const [],
    File? imageFile,
    String severity = 'low',
    String? projectId,
    String? tabUrl,
  }) async {
    try {
      print('[BugReport Service] Starting bug report creation...');
      print('\nInput validation:');
      print('Description: ${description.length} characters');
      print('Recipient Name: $recipientName');
      print('CC Recipients: $ccRecipients');
      print('Image File: ${imageFile?.path}');
      print('Severity: $severity');
      print('Project ID: $projectId');
      print('Tab URL: $tabUrl');

      if (description.isEmpty) {
        throw Exception('Description cannot be empty');
      }
      if (recipientName.isEmpty) {
        throw Exception('Recipient name cannot be empty');
      }

      final formData = FormData();
      
      print('\nBuilding form data fields:');
      formData.fields.addAll([
        MapEntry('description', description),
        MapEntry('recipient_name', recipientName),
        MapEntry('severity', severity),
        if (projectId != null) MapEntry('project_id', projectId),
        if (tabUrl != null) MapEntry('tab_url', tabUrl),
        if (ccRecipients.isNotEmpty) MapEntry('cc_recipients', ccRecipients.join(',')),
      ]);

      print('\nForm data fields added:');
      for (var field in formData.fields) {
        print('${field.key}: ${field.value}');
      }

      if (imageFile != null) {
        print('\nProcessing image file:');
        print('File path: ${imageFile.path}');
        
        final bytes = await imageFile.readAsBytes();
        print('File size: ${bytes.length} bytes');
        
        if (bytes.isEmpty) {
          throw Exception('Image file is empty');
        }

        final extension = path.extension(imageFile.path).toLowerCase();
        final mimeType = lookupMimeType(imageFile.path);
        print('File extension: $extension');
        print('Detected MIME type: $mimeType');

        String contentType;
        String mediaType;
        if (mimeType?.startsWith('video/') == true || 
            ['.mp4', '.mov', '.3gp'].contains(extension)) {
          mediaType = 'video';
          contentType = mimeType ?? 'video/mp4';
          print('Identified as video file');
        } else {
          mediaType = 'image';
          contentType = mimeType ?? 'image/png';
          print('Identified as image file');
        }

        final fileName = '${mediaType}-${DateTime.now().millisecondsSinceEpoch}$extension';
        print('Generated filename: $fileName');
        
        formData.files.add(
          MapEntry(
            'file',
            MultipartFile.fromBytes(
              bytes,
              filename: fileName,
              contentType: MediaType.parse(contentType),
            ),
          ),
        );
        formData.fields.add(MapEntry('media_type', mediaType));
        print('File added to form data with media type: $mediaType');
      }

      print('\nPreparing to send request to: ${ApiConstants.baseUrl}/bug-reports/upload');
      final headers = await _getAuthHeaders();
      print('Request headers: $headers');

      final response = await _dio.post(
        '${ApiConstants.baseUrl}/bug-reports/upload',
        data: formData,
        options: Options(
          headers: headers,
          validateStatus: (status) => status! < 500,
        ),
      );

      print('\nResponse received:');
      print('Status code: ${response.statusCode}');
      print('Response data: ${response.data}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to create bug report: ${response.statusCode} - ${response.data}');
      }

      print('\nBug report created successfully');
      // Clear caches after successful creation
      _cachedBugReports = null;
      _commentCache.clear();
      print('Caches cleared');
      
    } catch (e, stackTrace) {
      print('\n[BugReport Service] Error creating bug report:');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> initializeBackgroundService() async {
    print('[BugReport Service] Initializing background service...');
    try {
      // Initialize WebSocket connection if not already connected
      if (_webSocketService == null) {
        await initializeWebSocket();
      }

      // Set up periodic ping to keep connection alive
      Timer.periodic(const Duration(seconds: 30), (timer) {
        if (_webSocketService != null && _webSocketService!.isConnected) {
          print('[BugReport Service] Sending ping to keep connection alive');
          _webSocketService!.sendPing();
        }
      });

      print('[BugReport Service] Background service initialized successfully');
    } catch (e) {
      print('[BugReport Service] Error initializing background service: $e');
      rethrow;
    }
  }
} 