import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/image_proxy_service.dart';

class ImagePreview extends StatelessWidget {
  final String? imageUrl;
  final String? mediaType;
  final String? tabUrl;
  final String description;
  final VoidCallback? onClose;
  final bool isInBugCard;

  const ImagePreview({
    Key? key,
    this.imageUrl,
    this.mediaType,
    this.tabUrl,
    this.description = '',
    this.onClose,
    this.isInBugCard = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isInBugCard) // Only show header in full view
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
          if (!isInBugCard) const SizedBox(height: 8),
          if (mediaType == 'video')
            _buildVideoPreview()
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
    return Container(
      height: isInBugCard ? 120 : 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (imageUrl != null) {
              final url = Uri.parse(imageUrl!);
              if (kIsWeb) {
                await launchUrl(url, mode: LaunchMode.platformDefault);
              } else {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            }
          },
          borderRadius: BorderRadius.circular(12),
          splashColor: Colors.purple.withOpacity(0.3),
          highlightColor: Colors.purple.withOpacity(0.2),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Play button with semi-transparent background
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              // Video indicator badge
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.videocam,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Video',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Text for full preview
              if (!isInBugCard)
                Positioned(
                  bottom: 16,
                  child: Column(
                    children: [
                      Text(
                        'Play Video in Chrome',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Click to open video',
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
} 