import 'dart:async';
import 'dart:convert';
import '../models/bug_report.dart';
import '../models/comment.dart';
import '../models/project.dart';
import '../models/user.dart';
import '../services/bug_report_service.dart';
import '../services/project_service.dart';
import '../services/user_service.dart';
import 'package:flutter/material.dart';

enum WebSocketEventType {
  bugReport,
  comment,
  project,
  user,
  notification
}

class WebSocketEventHandler {
  final BugReportService _bugReportService;
  final ProjectService _projectService;
  final UserService _userService;
  
  final _bugReportController = StreamController<BugReport>.broadcast();
  final _commentController = StreamController<Comment>.broadcast();
  final _projectController = StreamController<Project>.broadcast();
  final _userController = StreamController<User>.broadcast();
  final _notificationController = StreamController<Map<String, dynamic>>.broadcast();

  WebSocketEventHandler(
    this._bugReportService,
    this._projectService,
    this._userService,
  );

  Stream<BugReport> get bugReportStream => _bugReportController.stream;
  Stream<Comment> get commentStream => _commentController.stream;
  Stream<Project> get projectStream => _projectController.stream;
  Stream<User> get userStream => _userController.stream;
  Stream<Map<String, dynamic>> get notificationStream => _notificationController.stream;

  void handleEvent(String message) {
    try {
      final data = jsonDecode(message);
      final type = data['type'];
      final payload = data['payload'];

      print('WebSocket event received - Type: $type');
      
      switch (type) {
        case 'bug_report':
          final action = payload['event'];
          _handleBugReportEvent(action, payload);
          break;
        case 'comment':
          final action = payload['event'];
          _handleCommentEvent(action, payload);
          break;
        case 'project':
          _handleProjectEvent(action, payload);
          break;
        case 'user':
          _handleUserEvent(action, payload);
          break;
        case 'notification':
          _handleNotificationEvent(payload);
          break;
        case 'pong':
          // Handle pong response
          print('Received pong from server');
          break;
        case 'system':
          // Handle system messages
          print('System message: ${payload['message']}');
          break;
        case 'error':
          print('WebSocket error: ${payload['message']}');
          break;
        default:
          print('Unknown event type: $type');
      }
    } catch (e, stackTrace) {
      print('Error handling WebSocket event: $e');
      print('Stack trace: $stackTrace');
    }
  }

  void _handleBugReportEvent(String action, Map<String, dynamic> payload) {
    try {
      print('Handling bug report event: $action');
      final bugReportData = payload['bug_report'] ?? payload;
      final bugReport = BugReport.fromJson(bugReportData);
      
      switch (action) {
        case 'created':
        case 'updated':
          print('Processing ${action} bug report #${bugReport.id}');
          _bugReportService.updateBugReportCache(bugReport);
          _bugReportController.add(bugReport);
          
          // Send notification for new bugs
          final lifecycleState = WidgetsBinding.instance.lifecycleState;
          if (action == 'created' || 
              lifecycleState == AppLifecycleState.paused || 
              lifecycleState == AppLifecycleState.inactive || 
              lifecycleState == AppLifecycleState.detached) {
            NotificationService().showBugNotification(
              title: 'New Bug Report #${bugReport.id}',
              body: '${bugReport.creator ?? "Someone"} reported: ${bugReport.description}',
              bugId: bugReport.id.toString(),
              creatorName: bugReport.creator,
              isInApp: lifecycleState == AppLifecycleState.resumed,
            );
          }
          break;
        case 'deleted':
          print('Processing deleted bug report #${bugReport.id}');
          _bugReportService.deleteBugReportFromCache(bugReport.id);
          _bugReportController.add(bugReport);
          break;
        default:
          print('Unknown bug report action: $action');
      }
    } catch (e, stackTrace) {
      print('Error handling bug report event: $e');
      print('Stack trace: $stackTrace');
    }
  }

  void _handleCommentEvent(String action, Map<String, dynamic> payload) {
    try {
      print('Handling comment event: $action');
      final comment = Comment.fromJson(payload['comment'] ?? payload);
      
      // Check if we've already processed this comment
      if (_processedCommentIds.contains(comment.id)) {
        print('Comment ${comment.id} already processed, skipping');
        return;
      }
      
      // Add to processed set
      _processedCommentIds.add(comment.id);
      
      switch (action) {
        case 'created':
          _bugReportService.addCommentToCache(comment);
          _commentController.add(comment);
          break;
        case 'updated':
          _bugReportService.updateCommentInCache(comment);
          _commentController.add(comment);
          break;
        case 'deleted':
          _bugReportService.deleteCommentFromCache(comment);
          _commentController.add(comment);
          break;
      }
    } catch (e) {
      print('Error handling comment event: $e');
    }
  }

  void _handleProjectEvent(String action, Map<String, dynamic> payload) {
    try {
      print('Handling project event: $action');
      final project = Project.fromJson(payload['project'] ?? payload);
      
      switch (action) {
        case 'created':
        case 'updated':
          _projectService.updateProjectCache(project);
          _projectController.add(project);
          break;
        case 'deleted':
          _projectService.deleteProjectFromCache(project.id);
          _projectController.add(project);
          break;
      }
    } catch (e) {
      print('Error handling project event: $e');
    }
  }

  void _handleUserEvent(String action, Map<String, dynamic> payload) {
    try {
      print('Handling user event: $action');
      final user = User.fromJson(payload['user'] ?? payload);
      
      switch (action) {
        case 'created':
        case 'updated':
          _userService.updateUserCache(user);
          _userController.add(user);
          break;
        case 'deleted':
          _userService.deleteUserFromCache(user.id);
          _userController.add(user);
          break;
      }
    } catch (e) {
      print('Error handling user event: $e');
    }
  }

  void _handleNotificationEvent(Map<String, dynamic> payload) {
    try {
      print('Handling notification event');
      _notificationController.add(payload);
    } catch (e) {
      print('Error handling notification event: $e');
    }
  }

  void dispose() {
    _bugReportController.close();
    _commentController.close();
    _projectController.close();
    _userController.close();
    _notificationController.close();
  }
} 