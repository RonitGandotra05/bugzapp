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

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _loadSavedNotifications();
    _setupStreams();
  }

  Future<void> _initializeNotifications() async {
    if (!_isInitialized) {
      await _notificationService.initialize();
      _isInitialized = true;
    }
  }

  Future<void> _loadSavedNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedNotifications = prefs.getString(_notificationsKey);
      if (savedNotifications != null) {
        final List<dynamic> notificationsList = jsonDecode(savedNotifications);
        setState(() {
          _notifications.clear();
          _notifications.addAll(
            notificationsList.map((item) => NotificationItem.fromJson(item)).toList()
          );
          _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        });
      }
    } catch (e) {
      print('Error loading saved notifications: $e');
    }
  }

  Future<void> _saveNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsJson = jsonEncode(
        _notifications.map((item) => item.toJson()).toList()
      );
      await prefs.setString(_notificationsKey, notificationsJson);
    } catch (e) {
      print('Error saving notifications: $e');
    }
  }

  void _setupStreams() {
    widget.bugReportStream.listen((bugReport) {
      final notificationId = 'bug_${bugReport.id}';
      _addNotification(
        NotificationItem(
          id: bugReport.id,
          title: 'New Bug Report #${bugReport.id}',
          message: bugReport.description,
          timestamp: bugReport.modifiedDate,
          type: NotificationType.bugReport,
          creatorName: bugReport.creator,
          assignedToName: bugReport.recipient,
          ccRecipients: bugReport.ccRecipients,
          uniqueId: notificationId,
        ),
      );

      _notificationService.showNotification(
        title: 'New Bug Report #${bugReport.id}',
        body: '${bugReport.creator ?? "Someone"} reported: ${bugReport.description}',
        payload: notificationId,
      );
    });

    widget.commentStream.listen((comment) {
      final notificationId = 'comment_${comment.bugReportId}_${comment.id}';
      _addNotification(
        NotificationItem(
          id: comment.bugReportId,
          title: 'New Comment on Bug #${comment.bugReportId}',
          message: comment.comment,
          timestamp: comment.createdAt,
          type: NotificationType.comment,
          creatorName: comment.userName,
          uniqueId: notificationId,
        ),
      );

      _notificationService.showNotification(
        title: 'New Comment on Bug #${comment.bugReportId}',
        body: '${comment.userName}: ${comment.comment}',
        payload: notificationId,
      );
    });
  }

  void _addNotification(NotificationItem notification) {
    final existingIndex = _notifications.indexWhere((n) => n.uniqueId == notification.uniqueId);
    
    setState(() {
      if (existingIndex != -1) {
        _notifications[existingIndex] = notification;
      } else {
        _notifications.insert(0, notification);
      }
      
      _notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
    
    _saveNotifications();
  }

  void _clearNotifications() {
    setState(() {
      _notifications.clear();
      _unreadCount = 0;
    });
    _notificationService.clearAllNotifications();
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
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