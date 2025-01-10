import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  late SharedPreferences _prefs;

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal();

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
        
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) {
        // Handle notification tap
      },
    );
  }

  // Show notification without sound and track read status
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    bool playSound = false,
  }) async {
    // Create a unique key for this notification
    final String notificationKey = '${title}_${body}_${payload ?? ''}';
    
    // Check if this notification was already shown
    final bool wasShown = await _hasBeenShown(notificationKey);
    if (wasShown) {
      return; // Skip if already shown
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'bug_channel',
      'Bug Reports',
      channelDescription: 'Notifications for bug reports and updates',
      importance: Importance.high,
      priority: Priority.high,
      playSound: false,
      enableVibration: false,
      styleInformation: BigTextStyleInformation(''),
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics = DarwinNotificationDetails(
      presentSound: false,
      presentBadge: true,
      presentAlert: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
    
    // Mark this notification as shown
    await _markAsShown(notificationKey);
  }

  // Check if a notification has been shown
  Future<bool> _hasBeenShown(String key) async {
    return _prefs.getBool('notification_$key') ?? false;
  }

  // Mark a notification as shown
  Future<void> _markAsShown(String key) async {
    await _prefs.setBool('notification_$key', true);
  }

  // Update badge count without sound
  Future<void> updateBadgeCount(int count) async {
    if (count == 0) {
      await clearAllNotifications();
      return;
    }
    try {
      await FlutterAppBadger.updateBadgeCount(count);
    } catch (e) {
      print('Error updating badge count: $e');
    }
  }

  // Clear all notifications
  Future<void> clearAllNotifications() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
    await FlutterAppBadger.removeBadge();
  }

  // Reset shown notifications tracking
  Future<void> resetNotificationTracking() async {
    final keys = _prefs.getKeys().where((key) => key.startsWith('notification_'));
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
} 