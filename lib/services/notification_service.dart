import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'navigation_service.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  late SharedPreferences _prefs;
  
  // Channel IDs
  static const String _bugChannelId = 'bug_notifications';
  static const String _commentChannelId = 'comment_notifications';
  
  // Notification IDs
  static const int _bugNotificationId = 1;
  static const int _commentNotificationId = 2;

  // Get vibration pattern based on platform
  Int64List? get _vibrationPattern {
    if (kIsWeb || !Platform.isAndroid) return null;
    return Int64List.fromList([0, 500, 200, 500]);
  }

  Future<void> initialize() async {
    if (kIsWeb) {
      print('Notifications are not fully supported on web platform');
      return;
    }

    // Initialize timezone
    tz.initializeTimeZones();

    // Initialize notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    await _notifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _handleNotificationTap,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }

    // Initialize SharedPreferences
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> _createNotificationChannels() async {
    if (kIsWeb || !Platform.isAndroid) return;

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
        
    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(
      AndroidNotificationChannel(
        _bugChannelId,
        'Bug Reports',
        description: 'Notifications for new bug reports',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        vibrationPattern: _vibrationPattern,
      ),
    );

    await androidPlugin.createNotificationChannel(
      AndroidNotificationChannel(
        _commentChannelId,
        'Comments',
        description: 'Notifications for new comments',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        vibrationPattern: _vibrationPattern,
      ),
    );
  }

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  // Generic showNotification method for backward compatibility
  Future<void> showNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
    bool isInApp = false,
  }) async {
    final notificationId = DateTime.now().millisecondsSinceEpoch % 100000;

    await _notifications.show(
      notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _bugChannelId,
          'Bug Reports',
          channelDescription: 'Notifications for new bug reports',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: !isInApp,
          enableVibration: !isInApp,
          sound: !isInApp ? const RawResourceAndroidNotificationSound('notification_sound') : null,
          color: Colors.purple,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: !isInApp,
          sound: !isInApp ? 'notification_sound.aiff' : null,
        ),
      ),
      payload: json.encode(payload),
    );
  }

  Future<void> showBugNotification({
    required String title,
    required String body,
    required String bugId,
    String? creatorName,
    bool isInApp = false,
  }) async {
    if (kIsWeb) {
      print('Notifications are not supported on web platform');
      return;
    }

    final notificationId = int.parse(bugId);
    final notificationKey = 'bug_$bugId';

    // Check if this notification was already shown
    if (await _wasNotificationShown(notificationKey)) return;

    await _notifications.show(
      notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _bugChannelId,
          'Bug Reports',
          channelDescription: 'Notifications for new bug reports',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: !isInApp,
          enableVibration: !isInApp,
          vibrationPattern: !isInApp ? _vibrationPattern : null,
          sound: !isInApp ? const RawResourceAndroidNotificationSound('notification_sound') : null,
          fullScreenIntent: !isInApp,
          category: AndroidNotificationCategory.message,
          color: Colors.purple,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: !isInApp,
          sound: !isInApp ? 'notification_sound.aiff' : null,
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
      payload: json.encode({
        'type': 'bug',
        'id': bugId,
        'creator': creatorName,
      }),
    );

    await _markNotificationAsShown(notificationKey);
  }

  Future<void> showCommentNotification({
    required String title,
    required String body,
    required String bugId,
    String? commenterName,
    bool isInApp = false,
  }) async {
    final notificationId = int.parse(bugId) + 1000; // Offset to avoid ID conflicts
    final notificationKey = 'comment_${bugId}_$commenterName';

    // Check if this notification was already shown
    if (await _wasNotificationShown(notificationKey)) return;

    await _notifications.show(
      notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _commentChannelId,
          'Comments',
          channelDescription: 'Notifications for new comments',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: !isInApp,
          enableVibration: !isInApp,
          sound: !isInApp ? const RawResourceAndroidNotificationSound('notification_sound') : null,
          color: Colors.purple,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: !isInApp,
          sound: !isInApp ? 'notification_sound.aiff' : null,
        ),
      ),
      payload: json.encode({
        'type': 'comment',
        'bugId': bugId,
        'commenter': commenterName,
      }),
    );

    await _markNotificationAsShown(notificationKey);
  }

  Future<bool> _wasNotificationShown(String key) async {
    final shownNotifications = _prefs.getStringList('shown_notifications') ?? [];
    return shownNotifications.contains(key);
  }

  Future<void> _markNotificationAsShown(String key) async {
    final shownNotifications = _prefs.getStringList('shown_notifications') ?? [];
    shownNotifications.add(key);
    // Keep only last 100 notifications to prevent excessive storage use
    if (shownNotifications.length > 100) {
      shownNotifications.removeRange(0, shownNotifications.length - 100);
    }
    await _prefs.setStringList('shown_notifications', shownNotifications);
  }

  void _handleNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;

    try {
      final payload = json.decode(response.payload!);
      if (payload['type'] == 'bug') {
        NavigationService.navigateToBug(int.parse(payload['id']));
      } else if (payload['type'] == 'comment') {
        NavigationService.navigateToBug(int.parse(payload['bugId']));
      }
    } catch (e) {
      print('Error handling notification tap: $e');
    }
  }

  Future<void> updateBadgeCount(int count) async {
    if (!_isAndroid) {
      await _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  Future<void> clearAllNotifications() async {
    await _notifications.cancelAll();
    await updateBadgeCount(0);
  }
} 