import 'dart:typed_data';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class ImageCacheService {
  static final _instance = ImageCacheService._internal();
  final _cacheManager = DefaultCacheManager();

  factory ImageCacheService() {
    return _instance;
  }

  ImageCacheService._internal();

  Future<Uint8List?> getImage(String url) async {
    try {
      final fileInfo = await _cacheManager.getFileFromCache(url);
      
      if (fileInfo != null) {
        print('Loading image from cache: $url');
        return await fileInfo.file.readAsBytes();
      }

      print('Downloading image: $url');
      final file = await _cacheManager.downloadFile(url);
      return await file.file.readAsBytes();
    } catch (e) {
      print('Error loading/caching image: $e');
      return null;
    }
  }

  Future<void> clearCache() async {
    await _cacheManager.emptyCache();
  }
} 