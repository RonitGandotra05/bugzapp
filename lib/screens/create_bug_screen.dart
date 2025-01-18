import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart';
import 'package:video_player/video_player.dart';
import 'package:universal_html/html.dart' as html;
import 'package:google_fonts/google_fonts.dart';
import '../widgets/video_thumbnail.dart';

class _CreateBugScreenState extends State<CreateBugScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _tabUrlController = TextEditingController();
  final _descriptionFocusNode = FocusNode();
  
  // User selection
  String? _selectedRecipientId;
  List<String> _selectedCCRecipients = [];
  String _selectedSeverity = 'low';
  String? _selectedProjectId;
  
  // Media handling
  File? _mediaFile;
  Uint8List? _webMediaBytes;
  String? _mediaType;  // 'image' or 'video'
  String? _mimeType;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isProcessingMedia = false;
  
  // Loading states
  bool _isLoading = false;
  bool _isInitializing = true;
  bool _isCameraInitialized = false;
  String? _lastImagePath;
  
  // Data
  List<User> _availableUsers = [];
  List<Project> _projects = [];
  final BugReportService _bugReportService = BugReportService();

  @override
  void initState() {
    super.initState();
    _loadData();
    
    // Add keyboard listener for submit on enter
    _descriptionFocusNode.addListener(() {
      if (!_descriptionFocusNode.hasFocus) {
        // Validate on focus loss
        _formKey.currentState?.validate();
      }
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _tabUrlController.dispose();
    _descriptionFocusNode.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _unfocusAll() {
    FocusScope.of(context).unfocus();
  }

  Future<bool> _onWillPop() async {
    if (_isLoading || _isProcessingMedia) {
      return false;
    }

    if (_descriptionController.text.isNotEmpty || 
        _mediaFile != null || 
        _selectedRecipientId != null || 
        _selectedProjectId != null) {
      return await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Discard Changes?', style: GoogleFonts.poppins()),
          content: Text(
            'You have unsaved changes. Are you sure you want to discard them?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Discard', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      ) ?? false;
    }
    return true;
  }

  Future<void> _retryLoadData() async {
    setState(() => _isLoading = true);
    await _loadData();
  }

  Future<void> _submitBugReport() async {
    print('\n[CreateBugScreen] Starting bug report submission...');
    print('Current State:');
    print('Description: ${_descriptionController.text.length} chars');
    print('Selected Recipient: $_selectedRecipientId');
    print('Selected Project: $_selectedProjectId');
    print('Has Media File: ${_mediaFile != null}');
    print('Has Web Media: ${_webMediaBytes != null}');
    print('Media Type: $_mediaType');
    print('MIME Type: $_mimeType');
    print('Severity: $_selectedSeverity');
    
    // 1. Check if data is still loading
    if (_isInitializing || _isLoading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait while data is loading...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 2. Check if required data is loaded
    if (_availableUsers.isEmpty || _projects.isEmpty) {
      print('[CreateBugScreen] Error: Required data not loaded');
      print('Available users: ${_availableUsers.length}');
      print('Available projects: ${_projects.length}');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Required data not loaded. Please try again.'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _retryLoadData,
          ),
        ),
      );
      return;
    }

    try {
      // 3. Validate description
      final description = _descriptionController.text.trim();
      if (description.isEmpty) {
        throw Exception('Description is required');
      }
      if (description.length < 10) {
        throw Exception('Description must be at least 10 characters long');
      }

      // 4. Validate recipient
      if (_selectedRecipientId == null || _selectedRecipientId!.isEmpty) {
        throw Exception('Please select a recipient');
      }
      final selectedUser = _availableUsers.firstWhere(
        (user) => user.id.toString() == _selectedRecipientId,
        orElse: () {
          print('[CreateBugScreen] Selected recipient not found:');
          print('Selected ID: $_selectedRecipientId');
          print('Available users: ${_availableUsers.map((u) => '${u.id}: ${u.name}').join(', ')}');
          throw Exception('Selected recipient not found in available users');
        },
      );

      // 5. Validate project
      if (_selectedProjectId == null || _selectedProjectId!.isEmpty) {
        throw Exception('Please select a project');
      }
      final selectedProject = _projects.firstWhere(
        (project) => project.id.toString() == _selectedProjectId,
        orElse: () {
          print('[CreateBugScreen] Selected project not found:');
          print('Selected ID: $_selectedProjectId');
          print('Available projects: ${_projects.map((p) => '${p.id}: ${p.name}').join(', ')}');
          throw Exception('Selected project not found in available projects');
        },
      );

      // 6. Validate media
      if (_mediaFile == null && _webMediaBytes == null) {
        throw Exception('Please add an image or video');
      }

      // 7. Validate media size based on type
      if (_mediaType == 'video') {
        if (_mediaFile != null) {
          final stat = await _mediaFile!.stat();
          if (stat.size > 16 * 1024 * 1024) {
            throw Exception('Video size exceeds 16MB limit');
          }
        } else if (_webMediaBytes != null && _webMediaBytes!.lengthInBytes > 16 * 1024 * 1024) {
          throw Exception('Video size exceeds 16MB limit');
        }
      } else {
        // Image validation
        if (_mediaFile != null) {
          final bytes = await _mediaFile!.readAsBytes();
          if (bytes.isEmpty) {
            throw Exception('Selected image is empty');
          }
          if (bytes.lengthInBytes > 10 * 1024 * 1024) {
            throw Exception('Image size exceeds 10MB limit');
          }
        } else if (_webMediaBytes != null) {
          if (_webMediaBytes!.isEmpty) {
            throw Exception('Selected image is empty');
          }
          if (_webMediaBytes!.lengthInBytes > 10 * 1024 * 1024) {
            throw Exception('Image size exceeds 10MB limit');
          }
        }
      }

      print('\n[CreateBugScreen] All validations passed:');
      print('Description: $description');
      print('Recipient: ${selectedUser.name} (ID: ${selectedUser.id})');
      print('Project: ${selectedProject.name} (ID: ${selectedProject.id})');
      print('Severity: $_selectedSeverity');
      print('Media Type: $_mediaType');
      print('Has Media File: ${_mediaFile != null}');
      print('Has Web Media: ${_webMediaBytes != null}');

      // Set loading state after all validations pass
      setState(() => _isLoading = true);

      // Submit the bug report
      await _bugReportService.uploadBugReport(
        description: description,
        recipientName: selectedUser.name,
        imageFile: _mediaFile,
        imageBytes: _webMediaBytes,
        severity: _selectedSeverity,
        projectId: _selectedProjectId,
        tabUrl: _tabUrlController.text.trim(),
        ccRecipients: _selectedCCRecipients,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bug report created successfully'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      print('[CreateBugScreen] Error creating bug report: $e');
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _submitBugReport,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    
    setState(() {
      _isInitializing = true;
      _isLoading = true;
    });

    try {
      print('[CreateBugScreen] Loading users and projects...');
      final users = await _bugReportService.fetchUsers();
      final projects = await _bugReportService.fetchProjects();
      
      if (!mounted) return;
      
      setState(() {
        _availableUsers = users;
        _projects = projects;
        _isLoading = false;
        _isInitializing = false;
      });

      print('[CreateBugScreen] Data loaded successfully:');
      print('Users: ${users.length}');
      print('Projects: ${projects.length}');
    } catch (e) {
      print('[CreateBugScreen] Error loading data: $e');
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
        _isInitializing = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to load required data. Please try again.'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _retryLoadData,
          ),
        ),
      );
    }
  }

  Future<void> _processMediaFile(XFile file) async {
    if (!mounted) return;
    
    setState(() => _isProcessingMedia = true);
    
    try {
      print('[Media] Processing file: ${file.path}');
      final extension = path.extension(file.path).toLowerCase();
      final mimeType = lookupMimeType(file.path);
      print('[Media] File extension: $extension, MIME type: $mimeType');
      
      final isVideo = mimeType?.startsWith('video/') == true || 
          ['.mp4', '.mov', '.3gp'].contains(extension);
      
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        
        if (bytes.isEmpty) {
          throw Exception('Selected file is empty');
        }
        
        if (isVideo) {
          if (bytes.lengthInBytes > 16 * 1024 * 1024) {
            throw Exception('Video size exceeds 16MB limit');
          }
          // For videos in web, store the bytes and set media type
          setState(() {
            _mediaFile = null;
            _webMediaBytes = bytes;  // Store the bytes for upload
            _mediaType = 'video';
            _mimeType = mimeType ?? 'video/mp4';  // Default to mp4 if mime type is null
            _lastImagePath = file.path;
          });
          print('[Media] Video file selected for web, size: ${bytes.length} bytes');
          print('[Media] MIME type: $_mimeType');
        } else {
          if (bytes.lengthInBytes > 10 * 1024 * 1024) {
            throw Exception('Image size exceeds 10MB limit');
          }
          setState(() {
            _webMediaBytes = bytes;
            _mediaFile = null;
            _mediaType = 'image';
            _mimeType = mimeType ?? 'image/png';  // Default to png if mime type is null
            _lastImagePath = null;
          });
        }
      } else {
        final path = file.path;
        final newFile = File(path);
        
        if (isVideo) {
          // For videos, check size but don't read bytes for preview
          final stat = await newFile.stat();
          if (stat.size > 16 * 1024 * 1024) {
            throw Exception('Video size exceeds 16MB limit');
          }

          setState(() {
            _mediaFile = newFile;
            _webMediaBytes = null;
            _mediaType = 'video';
            _mimeType = mimeType ?? 'video/mp4';  // Default to mp4 if mime type is null
            _lastImagePath = path;
          });
          print('[Media] Video file selected for mobile, size: ${stat.size} bytes');
          print('[Media] MIME type: $_mimeType');
        } else {
          // For images, read bytes for preview
          final bytes = await newFile.readAsBytes();
          if (!mounted) return;
          
          if (bytes.lengthInBytes > 10 * 1024 * 1024) {
            throw Exception('Image size exceeds 10MB limit');
          }

          setState(() {
            _mediaFile = newFile;
            _webMediaBytes = null;
            _mediaType = 'image';
            _mimeType = mimeType ?? 'image/png';  // Default to png if mime type is null
            _lastImagePath = null;
          });
        }
      }
      
      print('[Media] Successfully processed media file:');
      print('Type: $_mediaType');
      print('MIME: $_mimeType');
      print('Has File: ${_mediaFile != null}');
      print('Has Web Bytes: ${_webMediaBytes != null}');
      print('File Path: ${_lastImagePath ?? "none"}');
    } catch (e) {
      print('[Media] Error processing media: $e');
      if (!mounted) return;
      
      _cleanupMedia();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessingMedia = false);
      }
    }
  }

  Future<void> _initializeVideoPlayer(String source) async {
    if (!mounted) return;
    
    if (_videoController != null) {
      await _videoController!.dispose();
      _videoController = null;
    }

    try {
      if (kIsWeb) {
        // For web, create a blob URL
        final blob = html.Blob([_webMediaBytes!], _mimeType);
        final url = html.Url.createObjectUrlFromBlob(blob);
        _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      } else {
        _videoController = VideoPlayerController.file(_mediaFile!);
      }

      if (!mounted) return;
      await _videoController!.initialize();
      
      if (!mounted) return;
      setState(() => _isVideoInitialized = true);
    } catch (e) {
      print('[Media] Error initializing video player: $e');
      if (!mounted) return;
      
      _cleanupMedia();
      rethrow;
    }
  }

  void _cleanupMedia() {
    if (_videoController != null) {
      _videoController!.dispose();
      _videoController = null;
    }
    
    if (kIsWeb && _webMediaBytes != null) {
      html.Url.revokeObjectUrl(_lastImagePath);
    }

    setState(() {
      _mediaFile = null;
      _webMediaBytes = null;
      _mediaType = null;
      _mimeType = null;
      _lastImagePath = null;
      _isVideoInitialized = false;
    });
  }

  Widget _buildMediaPreview() {
    if (_isProcessingMedia) {
      return const Center(child: CircularProgressIndicator());
    }

    // Early return if no media
    if (_mediaType == null || (_mediaFile == null && _webMediaBytes == null && _lastImagePath == null)) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _mediaType == 'video' ? Icons.videocam : Icons.image,
                size: 16,
                color: Colors.green[700],
              ),
              const SizedBox(width: 8),
              Text(
                _mediaType == 'video' ? 'Video Preview' : 'Image Preview',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.green[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_mediaType == 'video')
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (!kIsWeb && _mediaFile != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: VideoThumbnail(videoFile: _mediaFile!),
                    )
                  else
                    const Icon(
                      Icons.play_circle_outline,
                      size: 48,
                      color: Colors.white54,
                    ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Text(
                      'Video ready for upload',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_mediaType == 'image')
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: kIsWeb && _webMediaBytes != null
                ? Image.memory(
                    _webMediaBytes!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 200,
                      width: double.infinity,
                      color: Colors.grey[200],
                      child: Icon(
                        Icons.broken_image,
                        color: Colors.grey[400],
                        size: 32,
                      ),
                    ),
                  )
                : !kIsWeb && _mediaFile != null
                  ? Image.file(
                      _mediaFile!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 200,
                        width: double.infinity,
                        color: Colors.grey[200],
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.grey[400],
                          size: 32,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _mediaType == 'video' ? 'Video ready to upload' : 'Image ready to upload',
                style: GoogleFonts.poppins(
                  color: Colors.green[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete, color: Colors.red),
                label: Text(
                  'Remove',
                  style: GoogleFonts.poppins(color: Colors.red),
                ),
                onPressed: _cleanupMedia,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showMediaPicker() async {
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Add Media', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.purple),
              title: Text('Camera', style: GoogleFonts.poppins()),
              subtitle: Text('Take a photo', style: GoogleFonts.poppins(fontSize: 12)),
              onTap: () => Navigator.pop(context, 'camera_photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.purple),
              title: Text('Video', style: GoogleFonts.poppins()),
              subtitle: Text('Record a video', style: GoogleFonts.poppins(fontSize: 12)),
              onTap: () => Navigator.pop(context, 'camera_video'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.purple),
              title: Text('Gallery', style: GoogleFonts.poppins()),
              subtitle: Text('Choose existing photo', style: GoogleFonts.poppins(fontSize: 12)),
              onTap: () => Navigator.pop(context, 'gallery_photo'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library, color: Colors.purple),
              title: Text('Video Gallery', style: GoogleFonts.poppins()),
              subtitle: Text('Choose existing video', style: GoogleFonts.poppins(fontSize: 12)),
              onTap: () => Navigator.pop(context, 'gallery_video'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    try {
      XFile? file;
      switch (action) {
        case 'camera_photo':
          file = await ImagePicker().pickImage(
            source: ImageSource.camera,
            imageQuality: 85,
            maxWidth: 1920,
            maxHeight: 1080,
          );
          break;
        case 'camera_video':
          file = await ImagePicker().pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(minutes: 5),
          );
          break;
        case 'gallery_photo':
          file = await ImagePicker().pickImage(
            source: ImageSource.gallery,
            imageQuality: 85,
            maxWidth: 1920,
            maxHeight: 1080,
          );
          break;
        case 'gallery_video':
          file = await ImagePicker().pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(minutes: 5),
          );
          break;
      }

      if (file != null) {
        await _processMediaFile(file);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting media: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildProjectDropdown() {
    print('[CreateBugScreen] Building project dropdown');
    print('Current selected project ID: $_selectedProjectId');
    print('Available projects: ${_projects.map((p) => '${p.id}: ${p.name}').join(', ')}');

    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: 'Project *',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.purple[300]!),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      value: _selectedProjectId,
      items: _projects.map((project) {
        return DropdownMenuItem(
          value: project.id.toString(),
          child: Text(project.name),
        );
      }).toList(),
      onChanged: (value) {
        print('[CreateBugScreen] Project selection changed to: $value');
        setState(() => _selectedProjectId = value);
      },
      validator: (value) {
        print('[CreateBugScreen] Validating project selection: $value');
        if (value == null || value.isEmpty) {
          return 'Project is required';
        }
        if (!_projects.any((p) => p.id.toString() == value)) {
          return 'Invalid project selected';
        }
        return null;
      },
    );
  }

  Widget _buildRecipientDropdown() {
    print('[CreateBugScreen] Building recipient dropdown');
    print('Current selected recipient ID: $_selectedRecipientId');
    print('Available users: ${_availableUsers.map((u) => '${u.id}: ${u.name}').join(', ')}');

    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: 'Recipient *',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.purple[300]!),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      value: _selectedRecipientId,
      items: _availableUsers.map((user) {
        return DropdownMenuItem(
          value: user.id.toString(),
          child: Text(user.name),
        );
      }).toList(),
      onChanged: (value) {
        print('[CreateBugScreen] Recipient selection changed to: $value');
        setState(() => _selectedRecipientId = value);
      },
      validator: (value) {
        print('[CreateBugScreen] Validating recipient selection: $value');
        if (value == null || value.isEmpty) {
          return 'Recipient is required';
        }
        if (!_availableUsers.any((u) => u.id.toString() == value)) {
          return 'Invalid recipient selected';
        }
        return null;
      },
    );
  }

  Widget _buildMediaButtons() {
    if (_isProcessingMedia) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(
          children: [
            IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: () async {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Select Media Type', style: GoogleFonts.poppins()),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.photo_camera),
                          title: Text('Take Photo', style: GoogleFonts.poppins()),
                          onTap: () async {
                            Navigator.pop(context);
                            final ImagePicker picker = ImagePicker();
                            final XFile? photo = await picker.pickImage(
                              source: ImageSource.camera,
                              imageQuality: 85,
                              maxWidth: 1920,
                              maxHeight: 1080,
                            );
                            if (photo != null) {
                              await _processMediaFile(photo);
                            }
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.videocam),
                          title: Text('Record Video', style: GoogleFonts.poppins()),
                          onTap: () async {
                            Navigator.pop(context);
                            final ImagePicker picker = ImagePicker();
                            final XFile? video = await picker.pickVideo(
                              source: ImageSource.camera,
                              maxDuration: const Duration(minutes: 5),
                            );
                            if (video != null) {
                              await _processMediaFile(video);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Text('Camera', style: GoogleFonts.poppins()),
          ],
        ),
        Column(
          children: [
            IconButton(
              icon: const Icon(Icons.photo_library),
              onPressed: () async {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Select Media Type', style: GoogleFonts.poppins()),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.photo),
                          title: Text('Choose Photo', style: GoogleFonts.poppins()),
                          onTap: () async {
                            Navigator.pop(context);
                            final ImagePicker picker = ImagePicker();
                            final XFile? photo = await picker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 85,
                              maxWidth: 1920,
                              maxHeight: 1080,
                            );
                            if (photo != null) {
                              await _processMediaFile(photo);
                            }
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.video_library),
                          title: Text('Choose Video', style: GoogleFonts.poppins()),
                          onTap: () async {
                            Navigator.pop(context);
                            final ImagePicker picker = ImagePicker();
                            final XFile? video = await picker.pickVideo(
                              source: ImageSource.gallery,
                              maxDuration: const Duration(minutes: 5),
                            );
                            if (video != null) {
                              await _processMediaFile(video);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Text('Gallery', style: GoogleFonts.poppins()),
          ],
        ),
      ],
    );
  }

  Widget _buildMediaSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _mediaFile == null && _webMediaBytes == null 
            ? Colors.red 
            : Colors.grey[300]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Media *',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_mediaFile == null && _webMediaBytes == null)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    'Required',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.red,
                    ),
                  ),
                ),
              if (_mediaType == 'video')
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    '(Video)',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.purple,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMediaButtons(),
          if (_mediaType != null && !_isProcessingMedia) 
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _mediaType == 'video' ? Icons.videocam : Icons.image,
                            size: 16,
                            color: Colors.green[700],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _mediaType == 'video' ? 'Video Preview' : 'Image Preview',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _cleanupMedia,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        iconSize: 20,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                  if (_mimeType != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Type: $_mimeType',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  if (_mediaType == 'video')
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (!kIsWeb && _mediaFile != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: VideoThumbnail(
                                videoFile: _mediaFile!,
                                fit: BoxFit.cover,
                              ),
                            )
                          else if (kIsWeb && _webMediaBytes != null)
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.black54,
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.play_circle_outline,
                                  size: 64,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.videocam,
                                    size: 16,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Video ready for upload',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_mediaType == 'image')
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: kIsWeb && _webMediaBytes != null
                        ? Image.memory(
                            _webMediaBytes!,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 200,
                              width: double.infinity,
                              color: Colors.grey[200],
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.grey[400],
                                size: 32,
                              ),
                            ),
                          )
                        : !kIsWeb && _mediaFile != null
                          ? Image.file(
                              _mediaFile!,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 200,
                                width: double.infinity,
                                color: Colors.grey[200],
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.grey[400],
                                  size: 32,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _mediaType == 'video' ? 'Video ready to upload' : 'Image ready to upload',
                        style: GoogleFonts.poppins(
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        label: Text(
                          'Remove',
                          style: GoogleFonts.poppins(color: Colors.red),
                        ),
                        onPressed: _cleanupMedia,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (_isProcessingMedia)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: GestureDetector(
        onTap: _unfocusAll,
        child: Scaffold(
      appBar: AppBar(
            title: Text('Create Bug Report', style: GoogleFonts.poppins()),
            actions: [
              if (_isLoading || _isProcessingMedia)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          body: _isInitializing
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
              key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _descriptionController,
                          focusNode: _descriptionFocusNode,
                    decoration: InputDecoration(
                            labelText: 'Description *',
                            alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.purple[300]!),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                            helperText: 'Minimum 10 characters',
                            helperStyle: TextStyle(color: Colors.grey[600]),
                          ),
                          maxLines: 5,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Description is required';
                            }
                            if (value.trim().length < 10) {
                              return 'Description must be at least 10 characters';
                            }
                            return null;
                          },
                  ),
                  const SizedBox(height: 16),
                        _buildProjectDropdown(),
                        const SizedBox(height: 16),
                        _buildRecipientDropdown(),
                        const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                            labelText: 'Severity *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.purple[300]!),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    value: _selectedSeverity,
                    items: ['low', 'medium', 'high'].map((severity) {
                      return DropdownMenuItem(
                        value: severity,
                              child: Text(severity.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedSeverity = value);
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _tabUrlController,
                          decoration: InputDecoration(
                            labelText: 'Tab URL (Optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.purple[300]!),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildMediaSection(),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: (_isLoading || _isProcessingMedia) ? null : _submitBugReport,
                      style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                          ),
                          child: Text(
                            _isLoading ? 'Creating Bug Report...' : 'Submit Bug Report',
                              style: GoogleFonts.poppins(
                              fontSize: 16,
                                fontWeight: FontWeight.w500,
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
} 