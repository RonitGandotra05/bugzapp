import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:typed_data';
import '../models/bug_report.dart';
import '../models/comment.dart';
import '../services/bug_report_service.dart';
import '../services/image_proxy_service.dart';
import '../widgets/image_preview.dart';
import 'package:url_launcher/url_launcher.dart';

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
  List<Comment> _comments = [];
  bool _isLoadingComments = false;
  bool _isSubmittingComment = false;
  Uint8List? _imageBytes;
  Timer? _refreshTimer;

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
    setState(() => _isLoadingComments = true);
    try {
      final comments = await widget.bugReportService.getComments(widget.bug.id);
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoadingComments = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingComments = false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error loading comments: $e')),
          );
        });
      }
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

  Future<void> _submitComment() async {
    if (_commentController.text.trim().isEmpty) return;

    setState(() {
      _isSubmittingComment = true;
    });

    try {
      await widget.bugReportService.addComment(
        widget.bug.id,
        _commentController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _commentController.clear();
          _isSubmittingComment = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding comment: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isSubmittingComment = false;
        });
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
          child: widget.mediaType == 'video'
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    color: Colors.black87,
                    child: const Icon(
                      Icons.play_circle_outline,
                      color: Colors.white,
                      size: 64,
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final url = Uri.parse(widget.imageUrl ?? '');
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
                  ),
                ],
              )
            : _imageBytes != null
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
                    : const Center(child: Text('No media available')),
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
              decoration: InputDecoration(
                hintText: 'Add a comment...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.purple[300]!),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              maxLines: null,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.purple[400],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSubmittingComment ? null : _submitComment,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: _isSubmittingComment
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
              ),
            ),
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
          if (widget.bug.ccRecipients.isNotEmpty)
            _buildDetailRow('CC', widget.bug.ccRecipients.join(", ")),
          _buildDetailRow('Project', widget.bug.projectName ?? 'No Project'),
          _buildDetailRow('Created', 
            _getFormattedTime(widget.bug.modifiedDate)),
          if (widget.tabUrl != null && widget.tabUrl!.isNotEmpty)
            _buildDetailRow('URL', widget.tabUrl!),
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

  String _formatTime(DateTime time) {
    // Format as IST date and time
    final istTime = time.add(const Duration(hours: 5, minutes: 30));
    return DateFormat("dd MMM yyyy, hh:mm a").format(istTime) + " IST";
  }

  String _getFormattedTime(DateTime time) {
    return _formatTime(time);
  }
} 