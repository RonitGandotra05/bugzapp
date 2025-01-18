import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:typed_data';
import '../services/image_proxy_service.dart';

class ImagePreview extends StatelessWidget {
  final String? imageUrl;
  final String? mediaType;
  final String? tabUrl;
  final String description;
  final VoidCallback? onClose;

  const ImagePreview({
    Key? key,
    this.imageUrl,
    this.mediaType,
    this.tabUrl,
    this.description = '',
    this.onClose,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                mediaType == 'video' ? Icons.videocam : Icons.image,
                size: 16,
                color: Colors.green[700],
              ),
              const SizedBox(width: 8),
              Text(
                mediaType == 'video' ? 'Video Preview' : 'Image Preview',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.green[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (onClose != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 20,
                  color: Colors.grey[600],
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (mediaType == 'video')
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.play_circle_outline,
                    size: 48,
                    color: Colors.white54,
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Text(
                      'Video will be uploaded',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl!,
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  width: double.infinity,
                  color: Colors.grey[200],
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.grey[400],
                    size: 32,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          color: Colors.black87,
          child: const Icon(
            Icons.play_circle_outline,
            size: 96,
            color: Colors.white54,
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 120),
            Text(
              'Video Preview',
              style: GoogleFonts.poppins(
                color: Colors.white54,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final url = Uri.parse(imageUrl ?? '');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play Video'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                textStyle: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Video will open in your default video player',
              style: GoogleFonts.poppins(
                color: Colors.white38,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }
} 