import 'package:flutter/material.dart';
import '../models/bug_report.dart';
import '../models/comment.dart';
import '../services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

enum NotificationType {
  bugReport,
  comment
}

class NotificationItem {
  final int id;
  final String title;
  final String message;
  final DateTime timestamp;
  final NotificationType type;
  final String? creatorName;
  final String? assignedToName;
  final List<String> ccRecipients;
  final String uniqueId;

  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.timestamp,
    required this.type,
    this.creatorName,
    this.assignedToName,
    this.ccRecipients = const [],
    required this.uniqueId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'type': type.toString(),
      'creatorName': creatorName,
      'assignedToName': assignedToName,
      'ccRecipients': ccRecipients,
      'uniqueId': uniqueId,
    };
  }

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as int,
      title: json['title'] as String,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp']),
      type: NotificationType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => NotificationType.bugReport,
      ),
      creatorName: json['creatorName'] as String?,
      assignedToName: json['assignedToName'] as String?,
      ccRecipients: List<String>.from(json['ccRecipients'] ?? []),
      uniqueId: json['uniqueId'] as String,
    );
  }
}

class NotificationBell extends StatefulWidget {
  final Stream<BugReport> bugReportStream;
  final Stream<Comment> commentStream;
  final Function(int) onBugTap;

  const NotificationBell({
    Key? key,
    required this.bugReportStream,
    required this.commentStream,
    required this.onBugTap,
  }) : super(key: key);

  @override
  _NotificationBellState createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final List<NotificationItem> _notifications = [];
  final NotificationService _notificationService = NotificationService();
  int _unreadCount = 0;
  bool _isInitialized = false;
  final String _notificationsKey = 'notifications_list';
  static const int maxNotifications = 50; // Limit number of notifications
  final Set<String> _processedNotifications = {};

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _setupStreams();
  }

  Future<void> _initializeNotifications() async {
    if (!_isInitialized) {
      await _notificationService.initialize();
      _isInitialized = true;
    }
  }

  void _setupStreams() {
    widget.bugReportStream.listen((bugReport) {
      // Only show notification for newly created bug reports
      final notificationId = 'bug_${bugReport.id}';
      
      // Skip if already processed
      if (_processedNotifications.contains(notificationId)) {
        print('[NotificationBell] Skipping duplicate bug report notification: $notificationId');
        return;
      }
      
      _processedNotifications.add(notificationId);
      print('[NotificationBell] Processing new bug report notification: $notificationId');
      
      _addNotification(
        NotificationItem(
          id: bugReport.id,
          title: 'New Bug Report',
          message: 'Bug #${bugReport.id}: ${bugReport.description}',
          timestamp: bugReport.modifiedDate,
          type: NotificationType.bugReport,
          creatorName: bugReport.creator,
          assignedToName: bugReport.recipient,
          ccRecipients: bugReport.ccRecipients,
          uniqueId: notificationId,
        ),
      );
    });

    widget.commentStream.listen((comment) {
      final notificationId = 'comment_${comment.bugReportId}_${comment.id}';
      
      // Skip if already processed
      if (_processedNotifications.contains(notificationId)) {
        print('[NotificationBell] Skipping duplicate comment notification: $notificationId');
        return;
      }
      
      _processedNotifications.add(notificationId);
      print('[NotificationBell] Processing new comment notification: $notificationId');
      
      _addNotification(
        NotificationItem(
          id: comment.bugReportId,
          title: 'New Comment',
          message: '${comment.userName}: ${comment.comment}',
          timestamp: comment.createdAt,
          type: NotificationType.comment,
          creatorName: comment.userName,
          uniqueId: notificationId,
        ),
      );
    });
  }

  void _addNotification(NotificationItem notification) {
    setState(() {
      // Check if notification with same uniqueId already exists
      final existingIndex = _notifications.indexWhere((n) => n.uniqueId == notification.uniqueId);
      if (existingIndex != -1) {
        print('[NotificationBell] Notification already exists: ${notification.uniqueId}');
        return;
      }
      
      // Add new notification at the beginning
      _notifications.insert(0, notification);
      print('[NotificationBell] Added new notification: ${notification.uniqueId}');
      
      // Keep only the latest maxNotifications
      if (_notifications.length > maxNotifications) {
        _notifications.removeRange(maxNotifications, _notifications.length);
      }
      
      // Increment unread count
      _unreadCount++;
    });
  }

  void _clearNotifications() {
    setState(() {
      _notifications.clear();
      _unreadCount = 0;
      _processedNotifications.clear();
    });
    _notificationService.clearAllNotifications();
  }

  String _formatTimestamp(DateTime timestamp) {
    // Always show IST time
    final ist = timestamp.add(const Duration(hours: 5, minutes: 30));
    return '${ist.day.toString().padLeft(2, '0')}/${ist.month.toString().padLeft(2, '0')}/${ist.year} ${ist.hour.toString().padLeft(2, '0')}:${ist.minute.toString().padLeft(2, '0')} IST';
  }

  String _getTimeDisplay(DateTime utcTime) {
    // Always show IST time instead of relative time
    return _formatTimestamp(utcTime);
  }

  Future<void> _showNotificationMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    await showMenu(
      context: context,
      position: position,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        if (_notifications.isEmpty)
          PopupMenuItem(
            enabled: false,
            child: Text(
              'No notifications',
              style: TextStyle(color: Colors.grey[600]),
            ),
          )
        else ...[
          ..._notifications.map((notification) => PopupMenuItem(
            value: notification,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        notification.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      _formatTimestamp(notification.timestamp),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  notification.message,
                  style: const TextStyle(fontSize: 13),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (notification.creatorName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'By: ${notification.creatorName}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
                const Divider(),
              ],
            ),
          )).toList(),
          PopupMenuItem(
            onTap: _clearNotifications,
            child: Row(
              children: [
                Icon(Icons.clear_all, color: Colors.grey[600]),
                const SizedBox(width: 8),
                Text(
                  'Clear all',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value is NotificationItem) {
        widget.onBugTap(value.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications),
          onPressed: () => _showNotificationMenu(context),
          color: Colors.black87,
        ),
        if (_notifications.isNotEmpty)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: const BoxConstraints(
                minWidth: 14,
                minHeight: 14,
              ),
              child: Text(
                '${_notifications.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
} 