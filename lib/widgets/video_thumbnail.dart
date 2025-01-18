import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

class VideoThumbnail extends StatefulWidget {
  final File videoFile;

  const VideoThumbnail({
    Key? key,
    required this.videoFile,
  }) : super(key: key);

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  Uint8List? _thumbnailBytes;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  Future<void> _generateThumbnail() async {
    try {
      final thumbnailBytes = await vt.VideoThumbnail.thumbnailData(
        video: widget.videoFile.path,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 512,
        quality: 75,
      );

      if (mounted) {
        setState(() {
          _thumbnailBytes = thumbnailBytes;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error generating video thumbnail: $e');
      if (mounted) {
        setState(() {
          _error = 'Error loading preview';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_thumbnailBytes != null) {
      return Image.memory(
        _thumbnailBytes!,
        height: 150,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    }

    return const Center(
      child: Icon(
        Icons.video_file,
        size: 48,
        color: Colors.white54,
      ),
    );
  }
} 