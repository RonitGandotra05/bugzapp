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