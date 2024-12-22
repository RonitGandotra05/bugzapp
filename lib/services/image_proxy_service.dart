import 'dart:typed_data';
import 'image_cache_service.dart';
import 'package:http/http.dart' as http;

class ImageProxyService {
  static final _cacheService = ImageCacheService();

  static Future<Uint8List?> getImageBytes(String? url) async {
    if (url == null) {
      return null;
    }
    
    try {
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print('Failed to load image: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error loading image: $e');
      return null;
    }
  }

  static Future<void> clearCache() async {
    await _cacheService.clearCache();
  }
} 