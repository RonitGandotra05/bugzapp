import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../constants/api_constants.dart';
import 'package:http/http.dart' as http;
import '../utils/token_storage.dart';

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();
  
  static Future<void> initialize() async {
    // Request permission
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Initialize local notifications
    const initializationSettingsAndroid = 
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettingsIOS = DarwinInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap
        _handleNotificationTap(details);
      },
    );

    // Get FCM token
    final token = await _firebaseMessaging.getToken();
    if (token != null) {
      await _updateDeviceToken(token);
    }

    // Listen for token refresh
    _firebaseMessaging.onTokenRefresh.listen(_updateDeviceToken);

    // Handle notifications when app is in background
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle notifications when app is in foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  static Future<void> _updateDeviceToken(String token) async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return;

    try {
      await http.post(
        Uri.parse('${ApiConstants.baseUrl}/users/$userId/device-token'),
        headers: await TokenStorage.getHeaders(),
        body: {'token': token},
      );
    } catch (e) {
      print('Error updating device token: $e');
    }
  }

  static Future<void> _firebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
    await _showLocalNotification(message);
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    await _showLocalNotification(message);
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final androidDetails = AndroidNotificationDetails(
      'bug_reports_channel',
      'Bug Reports',
      channelDescription: 'Notifications for bug reports',
      importance: Importance.high,
      priority: Priority.high,
    );

    final iosDetails = const DarwinNotificationDetails();

    await _localNotifications.show(
      message.hashCode,
      message.notification?.title,
      message.notification?.body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: message.data['bug_id'],
    );
  }

  static void _handleNotificationTap(NotificationResponse details) {
    // Navigate to bug details when notification is tapped
    // You'll need to implement this using your navigation system
  }
} 