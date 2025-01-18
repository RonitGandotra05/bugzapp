import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'dart:convert';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final _player = AudioPlayer();

  Future<void> initialize() async {
    if (kIsWeb) {
      print('Notifications are not fully supported on web platform');
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
      },
    );

    // Request permissions for iOS
    if (!kIsWeb && Platform.isIOS) {
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            sound: true,
          );
    }

    // Load notification sound
    if (!kIsWeb) {
      await _player.setAsset('assets/sounds/notification.mp3');
    }
  }

  Future<void> showNotification({
    required String title,
    required String body,
    required Map<String, dynamic> payload,
    bool isInApp = true,
  }) async {
    if (kIsWeb) {
      print('Notifications are not supported on web platform');
      return;
    }

    if (!isInApp) {
      await _player.seek(Duration.zero);
      await _player.play();
    }

    const androidDetails = AndroidNotificationDetails(
      'bug_reports',
      'Bug Reports',
      channelDescription: 'Notifications for bug reports',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.message,
      fullScreenIntent: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      notificationDetails,
      payload: json.encode(payload),
    );
  }

  Future<void> showBugNotification({
    required String title,
    required String body,
    required String bugId,
    String? creatorName,
    bool isInApp = true,
  }) async {
    if (kIsWeb) {
      print('Notifications are not supported on web platform');
      return;
    }

    if (!isInApp) {
      await _player.seek(Duration.zero);
      await _player.play();
    }

    const androidDetails = AndroidNotificationDetails(
      'bug_reports',
      'Bug Reports',
      channelDescription: 'Notifications for bug reports',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.message,
      fullScreenIntent: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().microsecondsSinceEpoch ~/ 1000,
      title,
      body,
      notificationDetails,
      payload: bugId,
    );
  }

  Future<void> showCommentNotification({
    required String title,
    required String body,
    required String bugId,
    bool isInApp = true,
  }) async {
    if (kIsWeb) {
      print('Notifications are not supported on web platform');
      return;
    }

    if (!isInApp) {
      await _player.seek(Duration.zero);
      await _player.play();
    }

    const androidDetails = AndroidNotificationDetails(
      'bug_reports',
      'Bug Reports',
      channelDescription: 'Notifications for bug reports',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.message,
      fullScreenIntent: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      DateTime.now().microsecondsSinceEpoch ~/ 1000,
      title,
      body,
      notificationDetails,
      payload: bugId,
    );
  }

  Future<void> clearAllNotifications() async {
    if (kIsWeb) {
      print('Notifications are not supported on web platform');
      return;
    }

    await _flutterLocalNotificationsPlugin.cancelAll();
  }

  void dispose() {
    if (!kIsWeb) {
      _player.dispose();
    }
  }
} 