import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../services/auth_service.dart';
import '../utils/token_storage.dart';

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
  bool _isDisposed = false;

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
    if (_isConnected || _isDisposed) return;

    try {
      final token = await _authService.getToken();
      if (token == null) {
        print('WebSocket connection skipped: Not authenticated');
        return;
      }

      // Don't verify token validity to prevent unnecessary logout
      // Just try to connect with the existing token
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
          if (_isDisposed) return;
          print('WebSocket message received: $message');
          if (message is String) {
            try {
              final data = jsonDecode(message);
              if (data['type'] == 'pong') {
                print('Received pong from server');
                return;
              }
              // Don't handle invalid token errors, just try to reconnect
              _messageController.add(data);
            } catch (e) {
              print('Error parsing WebSocket message: $e');
            }
          }
        },
        onError: (error) {
          if (_isDisposed) return;
          print('WebSocket error: $error');
          _handleConnectionError(error);
        },
        onDone: () {
          if (_isDisposed) return;
          print('WebSocket connection closed');
          _isConnected = false;
          _handleConnectionError('Connection closed');
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (_isDisposed) return;
      print('WebSocket connection error: $e');
      _handleConnectionError(e);
    }
  }

  void _handleConnectionError(dynamic error) {
    if (_isDisposed) return;
    _isConnected = false;
    _pingTimer?.cancel();
    
    // Don't try to reconnect if we're in the middle of an upload
    if (error.toString().contains('token')) {
      print('Token-related WebSocket error, not attempting reconnect: $error');
      return;
    }
    
    // Always try to reconnect with backoff
    final backoffDuration = Duration(seconds: pow(2, _reconnectAttempts).toInt());
    print('Attempting to reconnect in ${backoffDuration.inSeconds} seconds...');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(backoffDuration, () async {
      if (_isDisposed) return;
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _reconnectAttempts++;
        connect();
      } else {
        print('Max reconnection attempts reached');
      }
    });
  }

  void send(dynamic data) {
    if (_isConnected && _channel != null && !_isDisposed) {
      try {
        final jsonString = jsonEncode(data);
        _channel!.sink.add(jsonString);
      } catch (e) {
        print('Error sending WebSocket message: $e');
      }
    }
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _messageController.close();
    _isConnected = false;
  }
} 