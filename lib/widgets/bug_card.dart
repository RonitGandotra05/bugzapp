import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bug_report.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'image_preview.dart';
import 'dart:typed_data';
import '../services/image_proxy_service.dart';
import '../services/bug_report_service.dart';
import 'bug_details_dialog.dart';

class BugCard extends StatelessWidget {
  final BugReport bug;
  final VoidCallback onStatusToggle;
  final VoidCallback onSendReminder;
  final VoidCallback? onDelete;

  const BugCard({
    Key? key,
    required this.bug,
    required this.onStatusToggle,
    required this.onSendReminder,
    this.onDelete,
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

  @override
  Widget build(BuildContext context) {
    // Get screen width to maintain consistent card size
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth > 600 ? 400.0 : screenWidth * 0.9;

    // Define colors based on status
    final backgroundColor = bug.status == BugStatus.assigned
        ? const Color(0xFFFFEBEE)  // More noticeable red background
        : const Color(0xFFE8F5E9); // More noticeable green background

    final borderColor = bug.status == BugStatus.assigned
        ? const Color(0xFFFFCDD2)  // Stronger red border
        : const Color(0xFFC8E6C9); // Stronger green border

    return Center(
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
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
                          if (onDelete != null)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: onDelete,
                              color: Colors.red[300],
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          IconButton(
                            icon: Icon(
                              bug.status == BugStatus.resolved
                                  ? Icons.refresh
                                  : Icons.check_circle_outline,
                              size: 20,
                            ),
                            onPressed: onStatusToggle,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            color: bug.status == BugStatus.resolved
                                ? Colors.orange
                                : Colors.green,
                          ),
                          if (bug.status == BugStatus.assigned)
                            IconButton(
                              icon: const Icon(Icons.notifications_none, size: 20),
                              onPressed: onSendReminder,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              color: Colors.blue,
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip({required String text, required Color color}) {
    final chipColor = text.toLowerCase().contains('assigned') 
        ? const Color(0xFFE53935)  // Brighter red for assigned
        : const Color(0xFF43A047); // Brighter green for resolved

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: chipColor.withOpacity(0.4),  // Increased border opacity
          width: 0.5,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            chipColor.withOpacity(0.25),  // Increased gradient opacity
            chipColor.withOpacity(0.2),
            chipColor.withOpacity(0.15),
          ],
        ),
      ),
      child: Text(
        text,
        style: GoogleFonts.poppins(
          color: chipColor,  // Full opacity for text
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
      ),
    );
  }
} 