import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ImageProxyService {
  static Future<Uint8List?> getImageBytes(String? url) async {
    if (url == null) return null;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      print('Failed to load image: ${response.statusCode}');
      return null;
    } catch (e) {
      print('Error loading image: $e');
      return null;
    }
  }
} 