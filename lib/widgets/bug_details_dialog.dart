import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:async';
import 'dart:typed_data';
import '../models/bug_report.dart';
import '../models/comment.dart';
import '../services/bug_report_service.dart';
import '../services/image_proxy_service.dart';
import '../widgets/image_preview.dart';

class BugDetailsDialog extends StatefulWidget {
  final BugReport bug;
  final String? imageUrl;
  final String? mediaType;
  final String? tabUrl;
  final BugReportService bugReportService;

  const BugDetailsDialog({
    Key? key,
    required this.bug,
    required this.imageUrl,
    required this.mediaType,
    required this.tabUrl,
    required this.bugReportService,
  }) : super(key: key);

  @override
  State<BugDetailsDialog> createState() => _BugDetailsDialogState();
}

class _BugDetailsDialogState extends State<BugDetailsDialog> {
  final TextEditingController _commentController = TextEditingController();
  Timer? _refreshTimer;
  List<Comment> _comments = [];
  bool _isLoading = false;
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    _loadComments();
    _loadImage();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30), 
      (_) => _loadComments()
    );
  }

  Future<void> _loadComments() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final comments = await widget.bugReportService.getBugComments(widget.bug.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      print('Error loading comments: $e');
    }
  }

  Future<void> _loadImage() async {
    if (widget.imageUrl != null) {
      final bytes = await ImageProxyService.getImageBytes(widget.imageUrl);
      if (mounted) {
        setState(() => _imageBytes = bytes);
      }
    }
  }

  Future<void> _addComment() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await widget.bugReportService.addComment(
        widget.bug.id,
        comment,
      );
      _commentController.clear();
      await _loadComments();
    } catch (e) {
      print('Error adding comment: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.imageUrl != null) _buildImagePreview(),
                      _buildDescription(),
                      const SizedBox(height: 16),
                      const Divider(),
                      _buildCommentsList(),
                    ],
                  ),
                ),
              ),
            ),
            _buildCommentInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImagePreview(
              imageUrl: widget.imageUrl,
              mediaType: widget.mediaType,
              tabUrl: widget.tabUrl,
              description: widget.bug.description,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _imageBytes != null
              ? Image.memory(
                  _imageBytes!,
                  fit: BoxFit.contain,
                )
              : widget.imageUrl != null
                  ? Image.network(
                      widget.imageUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        );
                      },
                    )
                  : const Center(child: Text('No image available')),
        ),
      ),
    );
  }

  Widget _buildDescription() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Description',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.bug.description,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.black87,
          ),
        ),
      ],
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
          const SizedBox(height: 8),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_comments.isEmpty)
            const Text('No comments yet')
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _comments.length,
              itemBuilder: (context, index) {
                final comment = _comments[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              comment.userName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              _formatTimestamp(comment.createdAt),
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(comment.comment),
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

  Widget _buildCommentInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Add a comment...',
                border: OutlineInputBorder(),
              ),
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _addComment,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bug Report #${widget.bug.id}',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailRow('Status', widget.bug.statusText),
          _buildDetailRow('Severity', widget.bug.severityText),
          _buildDetailRow('Created By', widget.bug.creator),
          _buildDetailRow('Assigned To', widget.bug.recipient),
          _buildDetailRow('Project', widget.bug.projectName ?? 'No Project'),
          _buildDetailRow('Created', 
            DateFormat('MMM d, h:mm a').format(widget.bug.modifiedDate)),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'N/A',
              style: GoogleFonts.poppins(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final localTimestamp = timestamp.toLocal();
    final difference = now.difference(localTimestamp);

    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d, h:mm a').format(localTimestamp);
    }
  }
} 