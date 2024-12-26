import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bug_report.dart';
import '../models/comment.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'image_preview.dart';
import 'dart:typed_data';
import '../services/image_proxy_service.dart';
import '../services/bug_report_service.dart';
import 'bug_details_dialog.dart';
import 'comment_dialog.dart';

class BugCard extends StatelessWidget {
  final BugReport bug;
  final VoidCallback onStatusToggle;
  final VoidCallback onSendReminder;
  final Function() onDelete;

  const BugCard({
    Key? key,
    required this.bug,
    required this.onStatusToggle,
    required this.onSendReminder,
    required this.onDelete,
  }) : super(key: key);

  void _showBugDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => BugDetailsDialog(
        bug: bug,
        imageUrl: bug.imageUrl,
        mediaType: bug.mediaType,
        tabUrl: bug.tabUrl,
        bugReportService: BugReportService(),
      ),
    );
  }

  void _showComments(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => CommentDialog(
        bugId: bug.id,
        bugReportService: BugReportService(),
      ),
    );
  }

  // Comments section
  Widget _buildCommentsSection() {
    return FutureBuilder<List<Comment>>(
      future: BugReportService().getComments(bug.id),
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

    return Center(
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: bug.status == BugStatus.assigned ? assignedGradient : resolvedGradient,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: bug.status == BugStatus.assigned 
                ? const Color(0xFFFF1744).withOpacity(0.3)  // Red border
                : const Color(0xFF00C853).withOpacity(0.3), // Green border
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (bug.status == BugStatus.assigned 
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
                            text: bug.severityText,
                            color: bug.severityColor,
                          ),
                          const SizedBox(width: 8),
                          _buildStatusChip(
                            text: bug.statusText,
                            color: bug.status == BugStatus.resolved
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ],
                      ),
                      // Actions
                      Row(
                        children: [
                          if (bug.status == BugStatus.assigned)
                            IconButton(
                              icon: const Icon(Icons.notifications_none, size: 20),
                              onPressed: onSendReminder,
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
                                    bug.status == BugStatus.resolved
                                        ? Icons.refresh
                                        : Icons.check_circle_outline,
                                    color: bug.status == BugStatus.resolved
                                        ? Colors.orange
                                        : Colors.green,
                                  ),
                                  title: Text(
                                    bug.status == BugStatus.resolved
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
                                      bug.status == BugStatus.resolved
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
                                          onDelete();
                                        },
                                        child: Text('Delete', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              } else if (value == 'toggle_status') {
                                onStatusToggle();
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
                    bug.description,
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
                  if (bug.imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        bug.imageUrl!,
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
                            if (bug.projectName != null)
                              Text(
                                bug.projectName!,
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[700],
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            Text(
                              'Assigned to: ${bug.recipient}',
                              style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        timeago.format(bug.modifiedDate.toLocal()),
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