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
import 'package:intl/intl.dart';

enum WebSocketEventType {
  bugReport,
  comment,
  project,
  user,
  notification
}

class WebSocketEventHandler {
  final BugReportService _bugReportService;
  final NotificationService _notificationService;
  final Set<String> _processedEvents = {};
  
  WebSocketEventHandler(this._bugReportService, this._notificationService);

  void handleEvent(Map<String, dynamic> event) {
    final type = event['type'] as String;
    final payload = event['payload'] as Map<String, dynamic>;
    final timestamp = payload['timestamp'] as String?;
    
    // Generate unique event ID based on type, action, and data
    String eventId;
    if (type == 'bug_report') {
      final action = payload['event'] as String;
      final bugReportData = payload['bug_report'] as Map<String, dynamic>;
      eventId = 'bug_${bugReportData['id']}_${action}_${timestamp ?? DateTime.now().toIso8601String()}';
    } else if (type == 'comment') {
      final action = payload['event'] as String;
      final commentData = payload['data'] as Map<String, dynamic>;
      eventId = 'comment_${commentData['bug_report_id']}_${commentData['id']}_${timestamp ?? DateTime.now().toIso8601String()}';
    } else {
      eventId = '${type}_${timestamp ?? DateTime.now().toIso8601String()}';
    }
    
    // Skip if already processed
    if (_processedEvents.contains(eventId)) {
      print('[WebSocket] Skipping duplicate event: $eventId');
      return;
    }
    
    print('[WebSocket] Processing event: $type with ID: $eventId');
    
    switch (type) {
      case 'bug_report':
        final action = payload['event'] as String;
        final bugReportData = payload['bug_report'];
        _handleBugReportEvent(action, bugReportData, eventId);
        break;
      case 'comment':
        final action = payload['event'] as String;
        final commentData = payload['data'];
        _handleCommentEvent(action, commentData, eventId);
        break;
      case 'pong':
        print('[WebSocket] Received pong response');
        break;
      default:
        print('[WebSocket] Unknown event type: $type');
    }
    
    // Add to processed events
    _processedEvents.add(eventId);
    
    // Clean up old events (keep last 100)
    if (_processedEvents.length > 100) {
      _processedEvents.remove(_processedEvents.first);
    }
  }

  void _handleBugReportEvent(String action, dynamic data, String eventId) {
    if (data == null) {
      print('[WebSocket] Bug report data is null');
      return;
    }

    try {
      final bugReport = BugReport.fromJson(data);
      print('[WebSocket] Processing bug report #${bugReport.id}, action: $action');
      
      switch (action) {
        case 'created':
          _bugReportService.updateBugReportCache(bugReport);
          print('[WebSocket] Added new bug report #${bugReport.id} to cache');
          _notificationService.showBugNotification(
            title: 'New Bug Report',
            body: 'Bug #${bugReport.id}: ${bugReport.description}',
            bugId: bugReport.id.toString(),
            creatorName: bugReport.creator,
          );
          break;
        case 'updated':
          _bugReportService.updateBugReportCache(bugReport);
          print('[WebSocket] Updated bug report #${bugReport.id} in cache');
          break;
        case 'deleted':
          _bugReportService.deleteBugReportFromCache(bugReport.id);
          print('[WebSocket] Deleted bug report #${bugReport.id} from cache');
          break;
        default:
          print('[WebSocket] Unknown bug report action: $action');
      }
    } catch (e) {
      print('[WebSocket] Error processing bug report event: $e');
    }
  }

  void _handleCommentEvent(String action, dynamic data, String eventId) {
    if (data == null) {
      print('[WebSocket] Comment data is null');
      return;
    }

    try {
      final comment = Comment.fromJson(data);
      print('[WebSocket] Processing comment #${comment.id} for bug #${comment.bugReportId}');
      
      switch (action) {
        case 'comment_created':
          _bugReportService.addCommentToCache(comment);
          print('[WebSocket] Added new comment to cache');
          _notificationService.showCommentNotification(
            title: 'New Comment',
            body: '${comment.userName}: ${comment.comment}',
            bugId: comment.bugReportId.toString(),
          );
          break;
        default:
          print('[WebSocket] Unknown comment action: $action');
      }
    } catch (e) {
      print('[WebSocket] Error processing comment event: $e');
    }
  }
} 