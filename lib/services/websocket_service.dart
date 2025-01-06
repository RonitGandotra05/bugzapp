import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../services/auth_service.dart';

class WebSocketService {
  final String baseUrl;
  final AuthService _authService;
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  final _messageController = StreamController<dynamic>.broadcast();

  WebSocketService(this.baseUrl, this._authService);

  Stream<dynamic> get messageStream => _messageController.stream;

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected) {
        send({"type": "ping"});
      }
    });
  }

  Future<void> connect() async {
    if (_isConnected) return;

    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('WebSocket connection skipped: Not authenticated');
        return;
      }

      // Convert HTTPS to WSS or HTTP to WS
      final wsUrl = baseUrl.replaceFirst('http:', 'ws:').replaceFirst('https:', 'wss:');
      final uri = Uri.parse('$wsUrl/ws?token=$token');

      print('Connecting to WebSocket: $uri');
      _channel = WebSocketChannel.connect(uri);
      
      // Wait for the connection to be established
      await _channel!.ready;
      
      _isConnected = true;
      _reconnectAttempts = 0;
      print('WebSocket connected successfully');
      _startPingTimer();

      _channel!.stream.listen(
        (message) {
          print('WebSocket message received: $message');
          if (message is String) {
            final data = jsonDecode(message);
            if (data['type'] == 'pong') {
              print('Received pong from server');
              return;
            }
          }
          _messageController.add(message);
        },
        onError: (error) {
          print('WebSocket error: $error');
          _handleConnectionError(error);
        },
        onDone: () {
          print('WebSocket connection closed');
          _isConnected = false;
          _handleConnectionError('Connection closed');
        },
      );
    } catch (e) {
      print('WebSocket connection error: $e');
      _handleConnectionError(e);
    }
  }

  void _handleConnectionError(dynamic error) {
    _isConnected = false;
    _pingTimer?.cancel();
    
    if (_reconnectAttempts < _maxReconnectAttempts) {
      final backoffDuration = Duration(seconds: pow(2, _reconnectAttempts).toInt());
      print('Attempting to reconnect in ${backoffDuration.inSeconds} seconds...');
      
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(backoffDuration, () {
        _reconnectAttempts++;
        connect();
      });
    } else {
      print('Max reconnection attempts reached. WebSocket connection failed.');
    }
  }

  void send(dynamic data) {
    if (_isConnected && _channel != null) {
      try {
        final jsonString = jsonEncode(data);
        _channel!.sink.add(jsonString);
      } catch (e) {
        print('Error sending WebSocket message: $e');
      }
    }
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _messageController.close();
    _isConnected = false;
  }
} 