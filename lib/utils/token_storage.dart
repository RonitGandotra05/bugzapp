import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class TokenStorage {
  static const String _tokenKey = 'auth_token';
  static const String _isAdminKey = 'is_admin';
  static const String _userIdKey = 'user_id';
  static const String _tokenExpiryKey = 'token_expiry';

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    
    // Set token expiry to 24 hours from now
    final expiry = DateTime.now().add(Duration(hours: 24)).toIso8601String();
    await prefs.setString(_tokenExpiryKey, expiry);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final expiryStr = prefs.getString(_tokenExpiryKey);

    if (token == null || expiryStr == null) {
      return null;
    }

    final expiry = DateTime.parse(expiryStr);
    if (DateTime.now().isAfter(expiry)) {
      // Token expired, clear all data
      await clearAll();
      return null;
    }

    return token;
  }

  static Future<void> deleteToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  static Future<void> saveIsAdmin(bool isAdmin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isAdminKey, isAdmin);
  }

  static Future<bool> getIsAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isAdminKey) ?? false;
  }

  static Future<void> saveUserId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_userIdKey, userId);
  }

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_isAdminKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_tokenExpiryKey);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();  // This will handle expiry check
    final userId = await getUserId();
    return token != null && userId != null;
  }
} 