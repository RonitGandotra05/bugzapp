import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bug_report.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'image_preview.dart';
import 'dart:typed_data';
import '../services/image_proxy_service.dart';
import '../services/bug_report_service.dart';
import 'bug_details_dialog.dart';

class BugCard extends StatefulWidget {
  final BugReport bug;
  final VoidCallback onStatusToggle;
  final VoidCallback onSendReminder;

  const BugCard({
    Key? key,
    required this.bug,
    required this.onStatusToggle,
    required this.onSendReminder,
  }) : super(key: key);

  @override
  State<BugCard> createState() => _BugCardState();
}

class _BugCardState extends State<BugCard> {
  // Store the image data
  Uint8List? imageData;
  bool isLoading = true;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    if (widget.bug.mediaType == 'video' || widget.bug.imageUrl == null) return;
    
    try {
      final data = await ImageProxyService.getImageBytes(widget.bug.imageUrl);
      if (mounted) {
        setState(() {
          imageData = data;
          isLoading = false;
          hasError = data == null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
          hasError = true;
        });
      }
    }
  }

  Widget _buildMediaPreview() {
    if (widget.bug.mediaType == null || widget.bug.imageUrl == null) {
      return Container(
        height: 200,
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported, color: Colors.grey[400], size: 48),
              const SizedBox(height: 8),
              Text(
                'No Image Available',
                style: GoogleFonts.poppins(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    } else if (widget.bug.mediaType == 'video') {
      return Container(
        height: 200,
        color: Colors.black87,
        child: const Center(
          child: Icon(
            Icons.play_circle_outline,
            size: 48,
            color: Colors.white,
          ),
        ),
      );
    } else {
      return Image.network(
        widget.bug.imageUrl ?? '',
        fit: BoxFit.cover,
        height: 200,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            height: 200,
            color: Colors.grey[200],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.broken_image, color: Colors.grey[400], size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'Failed to Load Image',
                    style: GoogleFonts.poppins(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => BugDetailsDialog(
            bug: widget.bug,
            imageUrl: widget.bug.imageUrl ?? 'N/A',
            tabUrl: widget.bug.tabUrl ?? 'N/A',
            mediaType: widget.bug.mediaType ?? 'image',
            bugReportService: BugReportService(),
          ),
        );
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 8,
        child: InkWell(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => BugDetailsDialog(
                bug: widget.bug,
                imageUrl: widget.bug.imageUrl ?? 'N/A',
                tabUrl: widget.bug.tabUrl ?? 'N/A',
                mediaType: widget.bug.mediaType ?? 'image',
                bugReportService: BugReportService(),
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: 'bug-image-${widget.bug.id}',
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ImagePreview(
                          imageUrl: widget.bug.imageUrl ?? 'N/A',
                          tabUrl: widget.bug.tabUrl ?? 'N/A',
                          mediaType: widget.bug.mediaType ?? 'image',
                          description: widget.bug.description,
                        ),
                      ),
                    );
                  },
                  child: _buildMediaPreview(),
                ),
              ),

              // Content Section
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: widget.bug.severityColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.bug.severityText,
                            style: GoogleFonts.poppins(
                              color: widget.bug.severityColor,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: widget.bug.status == BugStatus.resolved
                                ? Colors.green.withOpacity(0.1)
                                : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.bug.statusText,
                            style: GoogleFonts.poppins(
                              color: widget.bug.status == BugStatus.resolved
                                  ? Colors.green
                                  : Colors.orange,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Description
                    Text(
                      widget.bug.description,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),

                    // Project Info
                    if (widget.bug.projectName != null) ...[
                      Text(
                        widget.bug.projectName!,
                        style: GoogleFonts.poppins(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],

                    // Assignment Info
                    Text(
                      'Assigned to: ${widget.bug.recipient}',
                      style: GoogleFonts.poppins(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),

                    Text(
                      timeago.format(widget.bug.modifiedDate.toLocal()),
                      style: GoogleFonts.poppins(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // Action Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: widget.onStatusToggle,
                      icon: Icon(
                        widget.bug.status == BugStatus.resolved
                            ? Icons.refresh
                            : Icons.check,
                        size: 20,
                      ),
                      label: Text(
                        widget.bug.status == BugStatus.resolved ? 'Reopen' : 'Resolve',
                        style: GoogleFonts.poppins(),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: widget.bug.status == BugStatus.resolved
                            ? Colors.orange
                            : Colors.green,
                      ),
                    ),
                    if (widget.bug.status == BugStatus.assigned) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: widget.onSendReminder,
                        icon: const Icon(Icons.notifications_none),
                        label: Text(
                          'Remind',
                          style: GoogleFonts.poppins(),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue,
                        ),
                      ),
                    ],
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