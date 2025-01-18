import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../constants/api_constants.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform;
import 'package:intl/intl.dart';
import 'dart:math';

class WebSocketService {
  final String baseUrl;
  final AuthService _authService;
  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  DateTime? _lastMessageTime;
  bool _isConnected = false;
  final _messageController = StreamController<dynamic>.broadcast();
  static const _pingInterval = Duration(seconds: 30);
  static const _reconnectInterval = Duration(seconds: 5);
  final Function()? onRefreshNeeded;
  bool _isReconnecting = false;
  int _connectionAttempts = 0;
  static const _maxConnectionAttempts = 3;
  DateTime? _lastConnectionAttempt;
  static const _connectionCooldown = Duration(seconds: 30);
  final _processedMessageIds = <String>{};

  WebSocketService(this.baseUrl, this._authService, {this.onRefreshNeeded});

  Stream<dynamic> get messageStream => _messageController.stream;
  bool get isConnected => _isConnected;
  DateTime? get lastMessageTime => _lastMessageTime;

  void sendPing() {
    if (_channel != null && _isConnected) {
      print('[WebSocket] Sending ping...');
      try {
        _channel!.sink.add(jsonEncode({
          'type': 'ping',
          'timestamp': DateTime.now().toIso8601String()
        }));
      } catch (e) {
        print('[WebSocket] Error sending ping: $e');
      }
    }
  }

  Future<void> initializeBackgroundService() async {
    // Skip background service initialization on web platform
    if (kIsWeb) {
      print('Background service is not supported on web platform');
      return;
    }

    // Request notification permissions first
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    
    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    } else if (Platform.isIOS) {
      await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    final service = FlutterBackgroundService();
    
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onBackgroundStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'bugzapp_websocket',
        initialNotificationTitle: 'BugZapp',
        initialNotificationContent: 'Connected and listening for updates',
        foregroundServiceNotificationId: 888,
        autoStartOnBoot: true,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onBackgroundStart,
        onBackground: (ServiceInstance service) async {
          await onBackgroundStart(service);
          return true;
        },
      ),
    );

    // Start the service
    await service.startService();
  }

  @pragma('vm:entry-point')
  static Future<bool> onBackgroundStart(ServiceInstance service) async {
    // Ensure the service stays alive
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
      service.setAutoStartOnBootMode(true);
    }

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    // Initialize notification service with proper channels
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    
    const androidNotificationChannel = AndroidNotificationChannel(
      'bugzapp_background',
      'BugZapp Background',
      description: 'Background notifications for BugZapp',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
      showBadge: true,
    );

    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
    );

    // Create the notification channel for Android
    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidNotificationChannel);
    }

    // Start WebSocket connection with retry mechanism
    final authService = AuthService();
    final wsService = WebSocketService('${ApiConstants.baseUrl}', authService);
    
    bool reconnecting = false;
    Timer? reconnectTimer;

    void startReconnectTimer() {
      reconnectTimer?.cancel();
      reconnectTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
        if (!wsService.isConnected && !reconnecting) {
          reconnecting = true;
          try {
            await wsService.connect();
          } finally {
            reconnecting = false;
          }
        }
      });
    }

    await wsService.connect();
    startReconnectTimer();

    // Listen for WebSocket messages in background
    wsService.messageStream.listen((message) async {
      if (message is String) {
        try {
          final data = jsonDecode(message);
          final type = data['type'];
          final payload = data['payload'];

          switch (type) {
            case 'bug_report':
              final action = payload['event'];
              if (action == 'created') {
                final bugReport = payload['bug_report'];
                final istTime = DateTime.now().add(Duration(hours: 5, minutes: 30));
                final formattedTime = DateFormat("dd MMM yyyy, hh:mm a").format(istTime) + " IST";
                
                await _showBackgroundNotification(
                  flutterLocalNotificationsPlugin,
                  'New Bug Report',
                  'Bug #${bugReport['id']}: ${bugReport['description']}',
                  {
                    'type': 'bug_report',
                    'id': bugReport['id'].toString(),
                    'action': action,
                  },
                );
              }
              break;
            case 'comment':
              final action = payload['event'];
              if (action == 'created') {
                final comment = payload['comment'];
                final istTime = DateTime.now().add(Duration(hours: 5, minutes: 30));
                final formattedTime = DateFormat("dd MMM yyyy, hh:mm a").format(istTime) + " IST";
                
                await _showBackgroundNotification(
                  flutterLocalNotificationsPlugin,
                  'New Comment',
                  'Bug #${comment['bug_report_id']}: ${comment['user_name']}: ${comment['comment']}',
                  {
                    'type': 'comment',
                    'bug_id': comment['bug_report_id'].toString(),
                    'action': action,
                  },
                );
              }
              break;
          }
        } catch (e) {
          print('Error processing background message: $e');
        }
      }
    });

    // Enhanced periodic check
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (service is AndroidServiceInstance) {
        if (await service.isForegroundService()) {
          service.setForegroundNotificationInfo(
            title: "BugZapp",
            content: wsService.isConnected 
              ? "Connected and listening for updates" 
              : "Attempting to reconnect...",
          );
        }
      }

      service.invoke('update');
    });

    return true;
  }

  static Future<void> _showBackgroundNotification(
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
    String title,
    String body,
    Map<String, String> payload,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      'bugzapp_background',
      'BugZapp Background',
      channelDescription: 'Background notifications for BugZapp',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('notification_sound'),
      ongoing: false,
      autoCancel: true,
      category: AndroidNotificationCategory.message,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      actions: [
        AndroidNotificationAction('open', 'Open'),
        AndroidNotificationAction('dismiss', 'Dismiss'),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'notification_sound.mp3',
      interruptionLevel: InterruptionLevel.timeSensitive,
      threadIdentifier: 'bugzapp_notifications',
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().microsecondsSinceEpoch ~/ 1000,
      title,
      body,
      notificationDetails,
      payload: jsonEncode(payload),
    );
  }

  Future<void> connect() async {
    if (_isConnected || _isReconnecting) {
      print('[WebSocket] Already connected or reconnecting, skipping connection attempt');
      return;
    }

    _isReconnecting = true;
    _lastConnectionAttempt = DateTime.now();
    _connectionAttempts++;

    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('[WebSocket] No token available');
        _isReconnecting = false;
        return;
      }

      final wsUrl = Uri.parse('${ApiConstants.wsUrl}/ws?token=$token');
      print('[WebSocket] Connecting to: $wsUrl');
      
      // Use WebSocketChannel.connect for all platforms
      _channel = WebSocketChannel.connect(wsUrl);
      print('[WebSocket] Channel created, setting up stream listener...');
      
      _channel!.stream.listen(
        (message) {
          print('[WebSocket] Received message: $message');
          _lastMessageTime = DateTime.now();
          _connectionAttempts = 0; // Reset attempts on successful message
          
          if (message is String) {
            try {
              final data = jsonDecode(message);
              final type = data['type'];
              final payload = data['payload'];
              final messageId = '${type}_${payload?['id'] ?? DateTime.now().millisecondsSinceEpoch}';
              
              print('[WebSocket] Processing message: $data');
              
              // Check for duplicate messages
              if (_processedMessageIds.contains(messageId)) {
                print('[WebSocket] Skipping duplicate message: $messageId');
                return;
              }
              _processedMessageIds.add(messageId);
              
              // Add message to controller
              _messageController.add(message);
              print('[WebSocket] Added message to stream: $type');
            } catch (e) {
              print('[WebSocket] Error parsing message: $e');
            }
          }
        },
        onError: (error) {
          print('[WebSocket] Stream error: $error');
          _handleDisconnect();
        },
        onDone: () {
          print('[WebSocket] Stream closed. Connected: $_isConnected');
          _handleDisconnect();
        },
        cancelOnError: false,
      );

      _isConnected = true;
      _isReconnecting = false;
      print('[WebSocket] Connected successfully');
      _startPingTimer();

    } catch (e) {
      print('[WebSocket] Connection error: $e');
      _isReconnecting = false;
      _handleDisconnect();
    }
  }

  void _handleRateLimit() {
    _isConnected = false;
    _cancelPingTimer();
    _channel?.sink.close();
    _channel = null;
    
    // Implement exponential backoff
    final backoffDuration = Duration(seconds: pow(2, _connectionAttempts).toInt());
    print('[WebSocket] Rate limit backoff: ${backoffDuration.inSeconds}s');
    
    Future.delayed(backoffDuration, () {
      _connectionAttempts = 0;
      connect();
    });
  }

  void _handleDisconnect() {
    if (!_isConnected) return;
    
    print('[WebSocket] Handling disconnect. Previous state: connected=$_isConnected');
    _isConnected = false;
    _isReconnecting = false;
    _cancelPingTimer();
    
    _channel?.sink.close();
    _channel = null;
    
    // Only attempt reconnection if not web platform and within limits
    if (!kIsWeb && _connectionAttempts < _maxConnectionAttempts) {
      print('[WebSocket] Starting reconnect timer for mobile');
      _startReconnectTimer();
    }
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    print('[WebSocket] Starting ping timer with interval: ${_pingInterval.inSeconds}s');
    _pingTimer = Timer.periodic(_pingInterval, (timer) {
      if (_isConnected && _channel != null) {
        try {
          print('[WebSocket] Sending ping');
          _channel?.sink.add(jsonEncode({
            'type': 'ping',
            'timestamp': DateTime.now().toIso8601String()
          }));
        } catch (e) {
          print('[WebSocket] Error sending ping: $e');
          _handleDisconnect();
        }
      } else {
        print('[WebSocket] Skip ping - not connected');
      }
    });
  }

  void _startReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isConnected && !_isReconnecting) {
        print('[WebSocket] Attempting to reconnect...');
        await connect();
      } else {
        timer.cancel();
      }
    });
  }

  void _cancelPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  Future<void> disconnect() async {
    _isConnected = false;
    _cancelPingTimer();
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _messageController.close();
  }
} 