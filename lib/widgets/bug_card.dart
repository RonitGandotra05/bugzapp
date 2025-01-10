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
  final VoidCallback onStatusToggle;
  final VoidCallback onDelete;
  final Future<void> Function() onSendReminder;
  final BugReportService bugReportService;
  final bool highlight;
  final bool isSelected;
  final Function(bool) onSelectionChanged;
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
    required this.onSelectionChanged,
    this.selectionMode = false,
  }) : super(key: key);

  @override
  _BugCardState createState() => _BugCardState();
}

class _BugCardState extends State<BugCard> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _commentsLoaded = false;
  List<Comment> _comments = [];
  bool _isLoadingComments = false;
  bool _isLoading = false;
  bool _isAddingComment = false;
  bool _shouldHighlight = false;
  late AnimationController _highlightController;
  late Animation<Color?> _highlightAnimation;

  String _formatToIST(DateTime utcTime) {
    final istTime = utcTime.add(const Duration(hours: 5, minutes: 30));
    return DateFormat("dd MMM yyyy, hh:mm a").format(istTime) + " IST";
  }

  String _formatTime(DateTime time) {
    // Format as IST date and time
    return '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _getFormattedTime() {
    final DateTime utcTime = widget.bug.modifiedDate;
    return _formatTime(utcTime);
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

    // Sort comments by creation date, most recent first
    final sortedComments = List.from(_comments)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final displayComments = sortedComments.take(3).toList();

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

  @override
  void initState() {
    super.initState();
    _shouldHighlight = widget.highlight;
    // Load comments immediately when card is created
    _loadComments();
    
    // Listen for comment updates
    widget.bugReportService.commentStream.listen((comment) {
      if (comment.bugReportId == widget.bug.id) {
        // Update the local comments list from cache
        if (mounted) {
          setState(() {
            _comments = widget.bugReportService.getCachedComments(widget.bug.id);
          });
        }
      }
    });

    _highlightController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    _highlightAnimation = ColorTween(
      begin: Colors.purple[100],
      end: Colors.transparent,
    ).animate(CurvedAnimation(
      parent: _highlightController,
      curve: Curves.easeOut,
    ));

    if (_shouldHighlight) {
      _highlightController.forward().then((_) {
        if (mounted) {
          setState(() {
            _shouldHighlight = false;
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(BugCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload comments if bug ID changes (e.g., during search)
    if (oldWidget.bug.id != widget.bug.id) {
      _loadComments();
    }
    
    // Only highlight if this specific bug is being highlighted
    if (widget.highlight && !oldWidget.highlight) {
      setState(() {
        _shouldHighlight = true;
      });
      _highlightController.reset();
      _highlightController.forward().then((_) {
        if (mounted) {
          setState(() {
            _shouldHighlight = false;
          });
        }
      });
    }
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

    // Load comments if not already loaded
    if (!_commentsLoaded && !_isLoadingComments) {
      _loadComments();
    }

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
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          decoration: BoxDecoration(
            color: _shouldHighlight ? _highlightAnimation.value : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: child!,
          ),
        );
      },
      child: StatefulBuilder(
        builder: (context, setState) => Center(
          child: GestureDetector(
            onLongPress: () {
              widget.onSelectionChanged(!widget.isSelected);
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
                          ? () => widget.onSelectionChanged(!widget.isSelected)
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
                                        // Debug print
                                        Builder(builder: (context) {
                                          print('CC Recipients: ${widget.bug.ccRecipients}');
                                          return const SizedBox.shrink();
                                        }),
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

                            // Add comments section at the end
                            if (_comments.isNotEmpty) _buildCommentsSection(),
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

  Future<void> _loadComments() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingComments = true;
    });

    try {
      final comments = await widget.bugReportService.getComments(widget.bug.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _commentsLoaded = true;
          _isLoadingComments = false;
        });
        print('Loaded ${comments.length} comments for bug ${widget.bug.id}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingComments = false;
          _commentsLoaded = true;
        });
        print('Error loading comments: $e');
      }
    }
  }
} 