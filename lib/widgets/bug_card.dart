import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../models/bug_report.dart';
import '../models/comment.dart';
import 'image_preview.dart';
import 'dart:typed_data';
import '../services/image_proxy_service.dart';
import '../services/bug_report_service.dart';
import 'bug_details_dialog.dart';
import 'comment_dialog.dart';

class BugCard extends StatefulWidget {
  final BugReport bug;
  final VoidCallback onStatusToggle;
  final VoidCallback onDelete;
  final VoidCallback onSendReminder;
  final BugReportService bugReportService;
  final bool highlight;
  final bool isSelected;
  final Function(bool)? onSelectionChanged;
  final bool selectionMode;

  const BugCard({
    Key? key,
    required this.bug,
    required this.onStatusToggle,
    required this.onDelete,
    required this.onSendReminder,
    required this.bugReportService,
    this.highlight = false,
    this.isSelected = false,
    this.onSelectionChanged,
    this.selectionMode = false,
  }) : super(key: key);

  @override
  _BugCardState createState() => _BugCardState();
}

class _BugCardState extends State<BugCard> with SingleTickerProviderStateMixin {
  late AnimationController _highlightController;
  late Animation<Color?> _highlightAnimation;
  bool _isExpanded = false;
  List<Comment> _comments = [];
  bool _isLoadingComments = false;
  bool _isLoading = false;
  bool _isAddingComment = false;
  bool _shouldHighlight = false;
  StreamSubscription<Comment>? _commentSubscription;

  String _formatToIST(DateTime utcTime) {
    final istTime = utcTime.add(const Duration(hours: 5, minutes: 30));
    return DateFormat("dd MMM yyyy, hh:mm a").format(istTime) + " IST";
  }

  String _formatTime(DateTime time) {
    // Format as IST date and time
    final istTime = time.add(const Duration(hours: 5, minutes: 30));
    return DateFormat("dd MMM yyyy, hh:mm a").format(istTime) + " IST";
  }

  String _getFormattedTime() {
    final DateTime utcTime = widget.bug.modifiedDate;
    return _formatTime(utcTime);
  }

  String _getTimeDisplay(DateTime utcTime) {
    // Always show IST time
    return _formatTime(utcTime);
  }

  void _showBugDetails(BuildContext context) async {
    try {
      // Pre-load comments
      await widget.bugReportService.getComments(widget.bug.id);
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => BugDetailsDialog(
            bug: widget.bug,
            imageUrl: widget.bug.imageUrl,
            mediaType: widget.bug.mediaType,
            tabUrl: widget.bug.tabUrl,
            bugReportService: widget.bugReportService,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading comments: $e')),
        );
      }
    }
  }

  void _showComments(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => CommentDialog(
        bugId: widget.bug.id,
        bugReportService: widget.bugReportService,
        onCommentAdding: (isAdding) {
          if (mounted) {
            setState(() {
              _isAddingComment = isAdding;
            });
          }
        },
      ),
    );
  }

  // Comments section
  Widget _buildCommentsSection() {
    if (_isLoadingComments) {
      return const SizedBox(
        height: 50,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_comments.isEmpty) {
      return const SizedBox.shrink();
    }

    // Use the already sorted comments list
    final displayComments = _comments.take(3).toList();

    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(Icons.comment_outlined, 
                  size: 14, 
                  color: Colors.grey[600]
                ),
                const SizedBox(width: 4),
                Text(
                  'Comments (${_comments.length})',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          ...displayComments.map((comment) => Container(
            margin: const EdgeInsets.only(bottom: 12),
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
                            _formatTime(comment.createdAt),
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
          if (_comments.length > 3)
            InkWell(
              onTap: () => _showBugDetails(context),
              child: Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      size: 14,
                      color: Colors.blue[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_comments.length - 3} more comments',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.blue[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCommentsList() {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Comments',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoadingComments)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_comments.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No comments yet',
                  style: GoogleFonts.poppins(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _comments.length,
              itemBuilder: (context, index) {
                // Comments are already sorted in the service, so we can use them directly
                final comment = _comments[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.purple[100],
                                  child: Text(
                                    comment.userName[0].toUpperCase(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.purple[700],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  comment.userName,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              _formatTime(comment.createdAt),
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          comment.comment,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.grey[800],
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _loadCachedComments() {
    if (!mounted) return;
    setState(() {
      _comments = widget.bugReportService.getCachedComments(widget.bug.id);
      // Sort comments by creation date (newest first)
      _comments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  @override
  void initState() {
    super.initState();
    _highlightController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );
    _highlightAnimation = ColorTween(
      begin: Colors.purple.withOpacity(0.2),
      end: Colors.transparent,
    ).animate(CurvedAnimation(
      parent: _highlightController,
      curve: Curves.easeOut,
    ));
    
    // Get comments from cache
    _loadCachedComments();
  }

  @override
  void didUpdateWidget(BugCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlight && !oldWidget.highlight) {
      _highlightController.forward(from: 0);
    }
    // Refresh cached comments when widget updates
    _loadCachedComments();
  }

  @override
  void dispose() {
    _highlightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth > 600 ? 400.0 : screenWidth * 0.9;

    final cardGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        widget.bug.status == BugStatus.resolved
            ? const Color(0xFFE8F5E9)
            : const Color(0xFFFFEBEE),
        widget.bug.status == BugStatus.resolved
            ? const Color(0xFFC8E6C9)
            : const Color(0xFFFFCDD2),
      ],
    );

    return AnimatedBuilder(
      animation: _highlightAnimation,
      builder: (context, child) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: widget.highlight ? _highlightAnimation.value : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: Colors.transparent,
        child: StatefulBuilder(
          builder: (context, setState) => Center(
            child: GestureDetector(
              onLongPress: () {
                if (widget.onSelectionChanged != null) {
                  widget.onSelectionChanged?.call(!widget.isSelected);
                }
              },
              child: Container(
                width: cardWidth,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  gradient: cardGradient,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: widget.isSelected ? Colors.blue : Colors.grey[200]!,
                    width: widget.isSelected ? 2 : 0.5,
                  ),
                ),
                child: Stack(
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.selectionMode
                            ? () {
                                if (widget.onSelectionChanged != null) {
                                  widget.onSelectionChanged?.call(!widget.isSelected);
                                }
                              }
                            : () => _showBugDetails(context),
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
                                  if (!widget.selectionMode) // Hide actions in selection mode
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
                                                    widget.onSendReminder();
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

                              // Image/Video preview
                              if (widget.bug.imageUrl != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: widget.bug.mediaType == 'video'
                                    ? Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Container(
                                            height: 120,
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              color: Colors.black87,
                                              image: DecorationImage(
                                                image: NetworkImage(widget.bug.imageUrl!),
                                                fit: BoxFit.cover,
                                                onError: (_, __) {},
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.play_arrow,
                                              color: Colors.white,
                                              size: 32,
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 8,
                                            right: 8,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.videocam,
                                                    color: Colors.white,
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Video',
                                                    style: GoogleFonts.poppins(
                                                      color: Colors.white,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Image.network(
                                        widget.bug.imageUrl!,
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
                                        if (widget.bug.ccRecipients.isNotEmpty) ...[
                                          Text(
                                            'CC: ${widget.bug.ccRecipients.join(", ")}',
                                            style: GoogleFonts.poppins(
                                              color: Colors.grey[600],
                                              fontSize: 11,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        if (widget.bug.tabUrl != null && widget.bug.tabUrl!.isNotEmpty)
                                          Text(
                                            'URL: ${widget.bug.tabUrl}',
                                            style: GoogleFonts.poppins(
                                              color: Colors.grey[600],
                                              fontSize: 11,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    _getFormattedTime(),
                                    style: GoogleFonts.poppins(
                                      color: Colors.grey[500],
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),

                              // Latest Comment Preview
                              if (_comments.isNotEmpty && !_isExpanded)
                                _buildLatestCommentPreview(),

                              // Full Comments Section when expanded
                              if (_isExpanded) _buildCommentsSection(),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (widget.isSelected)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
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

  // Latest Comment Preview
  Widget _buildLatestCommentPreview() {
    if (_comments.isEmpty) return const SizedBox.shrink();

    final latestComment = _comments.first; // Already sorted, first is latest
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.comment_outlined, 
              size: 14, 
              color: Colors.grey[600]
            ),
            const SizedBox(width: 4),
            Text(
              'Latest Comment',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                fontSize: 11,
                color: Colors.grey[700],
              ),
            ),
            const Spacer(),
            Text(
              '${_comments.length} comments',
              style: GoogleFonts.poppins(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: Colors.grey[200],
              child: Text(
                latestComment.userName[0].toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: 8,
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
                        latestComment.userName,
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
                        _formatTime(latestComment.createdAt),
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    latestComment.comment,
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
      ],
    );
  }
} 