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

  const ImagePreview({
    Key? key,
    required this.imageUrl,
    required this.mediaType,
    required this.tabUrl,
    required this.description,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          mediaType?.toUpperCase() ?? '',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        actions: [
          if (tabUrl != null && tabUrl!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'Open page in browser',
              onPressed: () async {
                final url = Uri.parse(tabUrl!);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open media in browser',
            onPressed: () async {
              final url = Uri.parse(imageUrl ?? '');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: mediaType == 'video'
                ? _buildVideoPreview()
                : FutureBuilder<Uint8List?>(
                    future: ImageProxyService.getImageBytes(imageUrl ?? ''),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                          ),
                        );
                      }

                      if (snapshot.hasError || !snapshot.hasData) {
                        print('Error loading image in preview: ${snapshot.error}');
                        print('Preview Image URL: ${imageUrl ?? ''}');
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.white54,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Failed to load image',
                                style: GoogleFonts.poppins(
                                  color: Colors.white54,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: SelectableText(
                                  imageUrl ?? '',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white24,
                                    fontSize: 10,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return PhotoView(
                        imageProvider: MemoryImage(snapshot.data!),
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.covered * 2,
                        backgroundDecoration: const BoxDecoration(
                          color: Colors.black,
                        ),
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image, size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  'Failed to load image',
                                  style: GoogleFonts.poppins(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          // Description Panel
          Container(
            width: double.infinity,
            color: Colors.black87,
            padding: const EdgeInsets.all(16),
            child: Text(
              description,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.video_file,
          size: 64,
          color: Colors.white54,
        ),
        const SizedBox(height: 16),
        Text(
          'Video Preview',
          style: GoogleFonts.poppins(
            color: Colors.white54,
            fontSize: 16,
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
              horizontal: 24,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
} 