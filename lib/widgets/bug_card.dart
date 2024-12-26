import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/bug_report.dart';
import '../models/comment.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'image_preview.dart';
import 'dart:typed_data';
import '../services/image_proxy_service.dart';
import '../services/bug_report_service.dart';
import 'bug_details_dialog.dart';
import 'comment_dialog.dart';

class BugCard extends StatefulWidget {
  final BugReport bug;
  final Future<void> Function() onSendReminder;
  final VoidCallback onStatusToggle;
  final Function() onDelete;

  const BugCard({
    Key? key,
    required this.bug,
    required this.onStatusToggle,
    required this.onSendReminder,
    required this.onDelete,
  }) : super(key: key);

  @override
  State<BugCard> createState() => _BugCardState();
}

class _BugCardState extends State<BugCard> {
  bool _isLoading = false;

  String _formatToIST(DateTime utcTime) {
    final istTime = utcTime.add(const Duration(hours: 5, minutes: 30));
    return DateFormat("dd MMM yyyy, hh:mm a").format(istTime) + " IST";
  }

  String _getTimeDisplay(DateTime utcTime) {
    final now = DateTime.now().toUtc();
    final difference = now.difference(utcTime);

    if (difference.inDays < 1) {
      // If less than 24 hours, show relative time
      return timeago.format(utcTime);
    } else {
      // Otherwise show formatted IST time
      return _formatToIST(utcTime);
    }
  }

  void _showBugDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => BugDetailsDialog(
        bug: widget.bug,
        imageUrl: widget.bug.imageUrl,
        mediaType: widget.bug.mediaType,
        tabUrl: widget.bug.tabUrl,
        bugReportService: BugReportService(),
      ),
    );
  }

  void _showComments(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => CommentDialog(
        bugId: widget.bug.id,
        bugReportService: BugReportService(),
      ),
    );
  }

  // Comments section
  Widget _buildCommentsSection() {
    return FutureBuilder<List<Comment>>(
      future: BugReportService().getComments(widget.bug.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();  // Don't show anything while loading
        }

        final comments = snapshot.data ?? [];
        if (comments.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.comment_outlined, 
                  size: 14, 
                  color: Colors.grey[600]
                ),
                const SizedBox(width: 4),
                Text(
                  'Comments (${comments.length})',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...comments.take(2).map((comment) => Container(  // Only show latest 2 comments
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.grey[200],
                    child: Text(
                      comment.userName[0].toUpperCase(),
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              comment.userName,
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '•',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              timeago.format(comment.createdAt),
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          comment.comment,
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey[700],
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )).toList(),
            if (comments.length > 2)  // Show "View all" if there are more comments
              TextButton(
                onPressed: () => _showBugDetails(context),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'View all ${comments.length} comments',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.blue[700],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth > 600 ? 400.0 : screenWidth * 0.9;

    // Define more vibrant, metallic-like gradients
    final assignedGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFFFF1744).withOpacity(0.1),  // Vibrant red
        const Color(0xFFD50000).withOpacity(0.05),  // Deep red
        const Color(0xFFFF5252).withOpacity(0.1),  // Light red
      ],
    );

    final resolvedGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF00C853).withOpacity(0.1),  // Vibrant green
        const Color(0xFF1B5E20).withOpacity(0.05),  // Deep green
        const Color(0xFF69F0AE).withOpacity(0.1),  // Light green
      ],
    );

    return StatefulBuilder(
      builder: (context, setState) => Center(
        child: Container(
          width: cardWidth,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            gradient: widget.bug.status == BugStatus.assigned ? assignedGradient : resolvedGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.bug.status == BugStatus.assigned 
                  ? const Color(0xFFFF1744).withOpacity(0.3)  // Red border
                  : const Color(0xFF00C853).withOpacity(0.3), // Green border
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (widget.bug.status == BugStatus.assigned 
                    ? const Color(0xFFFF1744) 
                    : const Color(0xFF00C853)).withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showBugDetails(context),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with Status and Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Status Chips
                        Row(
                          children: [
                            _buildStatusChip(
                              text: widget.bug.severityText,
                              color: widget.bug.severityColor,
                            ),
                            const SizedBox(width: 8),
                            _buildStatusChip(
                              text: widget.bug.statusText,
                              color: widget.bug.status == BugStatus.resolved
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ],
                        ),
                        // Actions
                        Row(
                          children: [
                            if (widget.bug.status == BugStatus.assigned)
                              IconButton(
                                icon: _isLoading 
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                      ),
                                    )
                                  : const Icon(Icons.notifications_none, size: 20),
                                onPressed: _isLoading 
                                  ? null 
                                  : () async {
                                      setState(() => _isLoading = true);
                                      try {
                                        await widget.onSendReminder();
                                      } finally {
                                        if (mounted) {
                                          setState(() => _isLoading = false);
                                        }
                                      }
                                    },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                color: Colors.blue,
                              ),
                            PopupMenuButton<String>(
                              itemBuilder: (context) => [
                                // Add resolve/unresolve option
                                PopupMenuItem(
                                  value: 'toggle_status',
                                  child: ListTile(
                                    leading: Icon(
                                      widget.bug.status == BugStatus.resolved
                                          ? Icons.refresh
                                          : Icons.check_circle_outline,
                                      color: widget.bug.status == BugStatus.resolved
                                          ? Colors.orange
                                          : Colors.green,
                                    ),
                                    title: Text(
                                      widget.bug.status == BugStatus.resolved
                                          ? 'Mark as Pending'
                                          : 'Mark as Resolved',
                                    ),
                                  ),
                                ),
                                // Delete option (for both assigned and resolved bugs)
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(Icons.delete, color: Colors.red),
                                    title: Text('Delete'),
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'delete') {
                                  // Show confirmation dialog
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text('Delete Bug Report'),
                                      content: Text(
                                        widget.bug.status == BugStatus.resolved
                                            ? 'Are you sure you want to delete this resolved bug report?'
                                            : 'Are you sure you want to delete this bug report?'
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            widget.onDelete();
                                          },
                                          child: Text('Delete', style: TextStyle(color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  );
                                } else if (value == 'toggle_status') {
                                  widget.onStatusToggle();
                                }
                              },
                              icon: Icon(
                                Icons.more_vert,
                                color: Colors.grey[600],
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Description
                    Text(
                      widget.bug.description,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),

                    // Image if available
                    if (widget.bug.imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          widget.bug.imageUrl!,
                          height: 120,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(),
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Footer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.bug.projectName != null)
                                Text(
                                  widget.bug.projectName!,
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[700],
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              Text(
                                'Assigned to: ${widget.bug.recipient}',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[600],
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _getTimeDisplay(widget.bug.modifiedDate.toLocal()),
                          style: GoogleFonts.poppins(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),

                    // Add comments section at the end
                    _buildCommentsSection(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip({required String text, required Color color}) {
    final isAssigned = text.toLowerCase().contains('assigned');
    final chipColor = isAssigned
        ? const Color(0xFFFF1744)  // Vibrant red
        : const Color(0xFF00C853); // Vibrant green

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            chipColor.withOpacity(0.3),
            chipColor.withOpacity(0.2),
            chipColor.withOpacity(0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: chipColor.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          color: chipColor,
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
      ),
    );
  }
} 