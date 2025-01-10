import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class TokenStorage {
  static const String _tokenKey = 'auth_token';
  static const String _isAdminKey = 'is_admin';
  static const String _userIdKey = 'user_id';
  static const String _tokenExpiryKey = 'token_expiry';
  static const String _lastRefreshKey = 'last_refresh';
  
  // Set token lifetime to 1 year
  static final Duration _tokenLifetime = Duration(days: 365);
  // Set refresh threshold to 7 days
  static final Duration _refreshThreshold = Duration(days: 7);

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    
    // Set expiry to 1 year from now
    final expiry = DateTime.now().add(_tokenLifetime);
    await prefs.setString(_tokenExpiryKey, expiry.toIso8601String());
    
    // Set last refresh time to now
    await prefs.setString(_lastRefreshKey, DateTime.now().toIso8601String());
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    
    if (token != null) {
      // Check if token needs refresh
      final lastRefreshStr = prefs.getString(_lastRefreshKey);
      if (lastRefreshStr != null) {
        final lastRefresh = DateTime.parse(lastRefreshStr);
        final now = DateTime.now();
        
        if (now.difference(lastRefresh) >= _refreshThreshold) {
          // Update expiry and last refresh time
          final newExpiry = now.add(_tokenLifetime);
          await prefs.setString(_tokenExpiryKey, newExpiry.toIso8601String());
          await prefs.setString(_lastRefreshKey, now.toIso8601String());
        }
      }
    }
    
    return token;
  }

  static Future<void> deleteToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_tokenExpiryKey);
  }

  static Future<void> saveIsAdmin(bool isAdmin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isAdminKey, isAdmin);
  }

  static Future<bool> getIsAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isAdminKey) ?? false;
  }

  static Future<void> saveUserId(dynamic userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (userId == null) return;
    
    int? userIdInt;
    if (userId is int) {
      userIdInt = userId;
    } else if (userId is String) {
      userIdInt = int.tryParse(userId);
    }
    
    if (userIdInt != null) {
      await prefs.setInt(_userIdKey, userIdInt);
    }
  }

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    // Clear all auth-related data
    await prefs.remove(_tokenKey);
    await prefs.remove(_isAdminKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_tokenExpiryKey);
    // Clear any other cached data
    await prefs.remove('current_user');
    await prefs.remove('user_data');
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final expiryStr = prefs.getString(_tokenExpiryKey);
    
    if (token == null || expiryStr == null) return false;
    
    try {
      final expiry = DateTime.parse(expiryStr);
      final now = DateTime.now();
      
      if (now.isAfter(expiry)) {
        // Token has expired
        await clearAll();
        return false;
      }
      
      // Check if token needs refresh
      final lastRefreshStr = prefs.getString(_lastRefreshKey);
      if (lastRefreshStr != null) {
        final lastRefresh = DateTime.parse(lastRefreshStr);
        if (now.difference(lastRefresh) >= _refreshThreshold) {
          // Update expiry and last refresh time
          final newExpiry = now.add(_tokenLifetime);
          await prefs.setString(_tokenExpiryKey, newExpiry.toIso8601String());
          await prefs.setString(_lastRefreshKey, now.toIso8601String());
        }
      }
      
      return true;
    } catch (e) {
      print('Error parsing token expiry: $e');
      return false;
    }
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_tokenExpiryKey);
  }
} 