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
import 'package:video_compress/video_compress.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:image_picker/image_picker.dart';

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
  
  // New variables
  double _uploadProgress = 0.0;
  bool _isCompressing = false;
  XFile? _webVideoFile;
  bool _isUploading = false;

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

  Future<bool> _validateMedia() async {
    if (_mediaFile == null && _webMediaBytes == null) {
      throw Exception('Please add an image or video');
    }

    print('\n[Media] Validating media before upload:');
    print('Media Type: $_mediaType');
    print('Has File: ${_mediaFile != null}');
    print('Has Web Bytes: ${_webMediaBytes != null}');

    try {
      if (_mediaType == 'video') {
        if (kIsWeb) {
          if (_webMediaBytes == null || _webMediaBytes!.isEmpty) {
            throw Exception('Video file is not loaded properly');
          }
          print('[Media] Web video size: ${_webMediaBytes!.length} bytes');
        } else {
          if (_mediaFile == null || !await _mediaFile!.exists()) {
            throw Exception('Video file is not loaded properly');
          }
          final fileSize = await _mediaFile!.length();
          print('[Media] Video file size: ${fileSize} bytes');
          if (fileSize == 0) {
            throw Exception('Video file is empty');
          }
        }
      } else if (_mediaType == 'image') {
        if (kIsWeb) {
          if (_webMediaBytes == null || _webMediaBytes!.isEmpty) {
            throw Exception('Image is not loaded properly');
          }
          if (_webMediaBytes!.length > 10 * 1024 * 1024) {
            throw Exception('Image size must be less than 10MB');
          }
        } else {
          if (_mediaFile == null || !await _mediaFile!.exists()) {
            throw Exception('Image file is not loaded properly');
          }
          final fileSize = await _mediaFile!.length();
          if (fileSize == 0) {
            throw Exception('Image file is empty');
          }
          if (fileSize > 10 * 1024 * 1024) {
            throw Exception('Image size must be less than 10MB');
          }
        }
      } else {
        throw Exception('Invalid media type');
      }

      print('[Media] Media validation successful');
      return true;
    } catch (e) {
      print('[Media] Media validation failed: $e');
      rethrow;
    }
  }

  Future<void> _submitBugReport() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      // Validate all required fields
      if (_descriptionController.text.trim().isEmpty) {
        throw Exception('Description is required');
      }
      if (_selectedRecipientId == null || _selectedRecipientId!.isEmpty) {
        throw Exception('Please select a recipient');
      }
      if (_selectedProjectId == null || _selectedProjectId!.isEmpty) {
        throw Exception('Please select a project');
      }

      // Create form data
      final formData = {
        'description': _descriptionController.text.trim(),
        'tab_url': _tabUrlController.text.trim(),
        'recipient_id': _selectedRecipientId,
        'project_id': _selectedProjectId,
      };

      // Upload with progress tracking
      if (_mediaFile != null || _webMediaBytes != null || _webVideoFile != null) {
        print('[Submit] Starting upload with media type: $_mediaType');
        print('[Submit] Media details:');
        print('Has File: ${_mediaFile != null}');
        print('Has Web Bytes: ${_webMediaBytes != null}');
        print('Has Web Video: ${_webVideoFile != null}');
        print('Media Type: $_mediaType');
        print('MIME Type: $_mimeType');

      await _bugReportService.uploadBugReport(
          description: formData['description']!,
          tabUrl: formData['tab_url']!,
          recipientId: formData['recipient_id']!,
          projectId: formData['project_id']!,
          mediaFile: _mediaFile,
          webMediaBytes: _webMediaBytes,
          webVideoFile: _webVideoFile,
          mediaType: _mediaType,
          mimeType: _mimeType,
          onProgress: (progress) {
            if (mounted) {
              print('[Submit] Upload progress: ${(progress * 100).toStringAsFixed(1)}%');
              setState(() {
                _uploadProgress = progress;
                _isUploading = true;
                _isLoading = true;
              });
            }
          },
        );
        print('[Submit] Upload completed successfully');
      } else {
        print('[Submit] Uploading bug report without media...');
        await _bugReportService.uploadBugReport(
          description: formData['description']!,
          tabUrl: formData['tab_url']!,
          recipientId: formData['recipient_id']!,
          projectId: formData['project_id']!,
        );
      }

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bug report submitted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      // Clear form
      _cleanupMedia();
      _descriptionController.clear();
      _tabUrlController.clear();
      setState(() {
        _selectedRecipientId = null;
        _selectedProjectId = null;
        _isLoading = false;
        _isUploading = false;
        _uploadProgress = 0.0;
      });

    } catch (e) {
      print('[Submit] Error submitting bug report: $e');
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isLoading = false;
        _isUploading = false;
        _uploadProgress = 0.0;
      });
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
    
    setState(() {
      _isProcessingMedia = true;
      _isCompressing = true;
    });
    
    try {
      print('[Media] Processing file: ${file.path}');
      final extension = path.extension(file.path).toLowerCase();
      final mimeType = lookupMimeType(file.path);
      print('[Media] File extension: $extension, MIME type: $mimeType');
      
      final isVideo = mimeType?.startsWith('video/') == true || 
          ['.mp4', '.mov', '.3gp'].contains(extension);
      
      if (isVideo) {
        print('[Media] Processing video file');
        setState(() {
          _mediaType = 'video';
          _mimeType = mimeType ?? 'video/mp4';
          _lastImagePath = null;
          _webMediaBytes = null;
        });

      if (kIsWeb) {
          // For web, store file reference and read bytes in chunks
          _mediaFile = null;
          _webVideoFile = file;
          
          // Read file in chunks to avoid memory issues
          final reader = html.FileReader();
          final blob = html.Blob([await file.readAsBytes()]);
          reader.readAsArrayBuffer(blob);
          
          await reader.onLoad.first;
          final bytes = reader.result as Uint8List;
          _webMediaBytes = bytes;
          print('[Media] Stored web video bytes: ${bytes.length} bytes');
        } else {
          // For mobile, use aggressive video compression
          try {
            print('[Media] Compressing video...');
            final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
              file.path,
              quality: VideoQuality.LowQuality,
              deleteOrigin: false,
              frameRate: 24,
              includeAudio: true,
              scale: 0.5, // Scale down video dimensions
            );

            if (mediaInfo?.file != null) {
              final originalSize = await File(file.path).length();
              final compressedSize = await mediaInfo!.file!.length();
              _mediaFile = mediaInfo.file!;
              print('[Media] Compressed video from ${originalSize} to ${compressedSize} bytes');
              print('[Media] Compression ratio: ${(compressedSize / originalSize * 100).toStringAsFixed(1)}%');
            } else {
              throw Exception('Failed to compress video');
            }
          } catch (e) {
            print('[Media] Error compressing video: $e');
            throw Exception('Failed to process video. Please try again.');
          }
        }
      } else {
        // Handle image files with optimized compression
        print('[Media] Processing image file');
        final validImageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic'];
        final isValidImage = validImageExtensions.contains(extension) || 
            (mimeType?.startsWith('image/') ?? false);
            
        if (!isValidImage) {
          throw Exception('Unsupported image format. Please use: JPG, PNG, GIF, WebP, BMP, or HEIC');
        }

        setState(() {
          _mediaType = 'image';
          // Set appropriate MIME type based on extension
          _mimeType = mimeType ?? switch (extension) {
            '.jpg' || '.jpeg' => 'image/jpeg',
            '.png' => 'image/png',
            '.gif' => 'image/gif',
            '.webp' => 'image/webp',
            '.bmp' => 'image/bmp',
            '.heic' => 'image/heic',
            _ => 'image/jpeg' // default to JPEG
          };
          _lastImagePath = null;
          _webVideoFile = null;
        });

        if (kIsWeb) {
          // For web, use more aggressive compression for supported formats
          final ImagePicker picker = ImagePicker();
          final XFile? compressedFile = await picker.pickImage(
            source: ImageSource.memory,
            imageQuality: _mimeType == 'image/gif' ? 100 : 60, // Don't compress GIFs
            maxWidth: 1280,
            maxHeight: 720,
            bytes: await file.readAsBytes(),
            preferredCameraDevice: CameraDevice.rear,
          );
          
          if (compressedFile != null) {
            _webMediaBytes = await compressedFile.readAsBytes();
            final originalSize = await file.length();
            print('[Media] Compressed web image from ${originalSize} to ${_webMediaBytes!.length} bytes');
            print('[Media] Compression ratio: ${(_webMediaBytes!.length / originalSize * 100).toStringAsFixed(1)}%');
          } else {
            throw Exception('Failed to process image');
          }
          _mediaFile = null;
        } else {
          // For mobile, use optimized compression for supported formats
          if (_mimeType == 'image/gif') {
            // For GIFs, use the original file without compression
            _mediaFile = File(file.path);
            print('[Media] Using original GIF file without compression');
          } else {
            final ImagePicker picker = ImagePicker();
            final XFile? compressedFile = await picker.pickImage(
              source: ImageSource.path,
              imageQuality: 60,
              maxWidth: 1280,
              maxHeight: 720,
              path: file.path,
              preferredCameraDevice: CameraDevice.rear,
            );
            
            if (compressedFile != null) {
              _mediaFile = File(compressedFile.path);
              final originalSize = await file.length();
              final compressedSize = await _mediaFile!.length();
              print('[Media] Compressed mobile image from ${originalSize} to ${compressedSize} bytes');
              print('[Media] Compression ratio: ${(compressedSize / originalSize * 100).toStringAsFixed(1)}%');
            } else {
              throw Exception('Failed to process image');
            }
          }
          _webMediaBytes = null;
        }
      }
      
      print('[Media] Successfully processed media file:');
      print('Type: $_mediaType');
      print('MIME: $_mimeType');
      print('Has File: ${_mediaFile != null}');
      print('Has Web Bytes: ${_webMediaBytes != null}');
      print('Has Web Video: ${_webVideoFile != null}');
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
        setState(() {
          _isProcessingMedia = false;
          _isCompressing = false;
        });
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
      _webVideoFile = null;
      _mediaType = null;
      _mimeType = null;
      _lastImagePath = null;
      _isVideoInitialized = false;
    });
  }

  Widget _buildMediaSection() {
      return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
            _buildMediaButton(
              icon: Icons.camera_alt,
              label: 'Take Photo',
              onPressed: () => _pickMedia(ImageSource.camera),
            ),
            _buildMediaButton(
              icon: Icons.photo_library,
              label: 'Gallery',
              onPressed: () => _pickMedia(ImageSource.gallery),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_webMediaBytes != null && _mediaType == 'image')
          ClipRRect(
          borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              _webMediaBytes!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
        ),
          )
        else if (_mediaFile != null && _mediaType == 'image')
          ClipRRect(
          borderRadius: BorderRadius.circular(12),
            child: Image.file(
              _mediaFile!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          )
        else if (_mediaType == 'video')
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
                  VideoThumbnail(videoFile: _mediaFile!)
                else
                  const Icon(
                    Icons.play_circle_outline,
                    color: Colors.white,
                    size: 64,
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
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
                    ),
                  ),
        if (_isProcessingMedia)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.purple[400]!),
                  ),
                ),
                const SizedBox(width: 8),
              Text(
                  _mediaType == 'video' ? 'Processing video...' : 'Processing image...',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                    color: Colors.purple[400],
                  ),
                ),
            ],
          ),
          ),
        if (_isUploading && _uploadProgress > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                LinearPercentIndicator(
                  lineHeight: 6,
                  percent: _uploadProgress,
                  backgroundColor: Colors.grey[200],
                  progressColor: Colors.purple[400],
                  barRadius: const Radius.circular(3),
                  padding: EdgeInsets.zero,
                  animation: true,
                  animateFromLastPercent: true,
                ),
                const SizedBox(height: 4),
                      Text(
                  'Uploading: ${(_uploadProgress * 100).toStringAsFixed(1)}%',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.purple[400],
                  ),
                      ),
                    ],
                  ),
          ),
      ],
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
                        _buildCompressionIndicator(),
                        _buildUploadProgress(),
                        const SizedBox(height: 24),
                        _buildSubmitButton(),
                ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildProjectDropdown() {
    // Implementation of _buildProjectDropdown method
    // This method should return a widget that allows the user to select a project
    // and update the _selectedProjectId state variable
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
        return DropdownMenuItem<String>(
          value: project.id.toString(),
          child: Text(project.name),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _selectedProjectId = value);
        }
      },
    );
  }

  Widget _buildRecipientDropdown() {
    // Implementation of _buildRecipientDropdown method
    // This method should return a widget that allows the user to select a recipient
    // and update the _selectedRecipientId state variable
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
        return DropdownMenuItem<String>(
          value: user.id.toString(),
          child: Text(user.name),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _selectedRecipientId = value);
        }
      },
    );
  }

  Widget _buildCompressionIndicator() {
    if (!_isCompressing) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
          ),
          const SizedBox(height: 8),
          Text(
            'Compressing video...',
            style: GoogleFonts.poppins(
              color: Colors.purple,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadProgress() {
    if (!_isUploading || _uploadProgress == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          LinearPercentIndicator(
            lineHeight: 8.0,
            percent: _uploadProgress,
            backgroundColor: Colors.grey[300],
            progressColor: Colors.purple,
            barRadius: const Radius.circular(4),
            animation: true,
            animateFromLastPercent: true,
          ),
          const SizedBox(height: 8),
          Text(
            'Uploading: ${(_uploadProgress * 100).toStringAsFixed(1)}%',
            style: GoogleFonts.poppins(
              color: Colors.purple,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _submitBugReport,
                      style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: _isLoading
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isUploading && _uploadProgress > 0)
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 160,
                          child: LinearPercentIndicator(
                            lineHeight: 8,
                            percent: _uploadProgress,
                            backgroundColor: Colors.white24,
                            progressColor: Colors.white,
                            barRadius: const Radius.circular(4),
                            padding: EdgeInsets.zero,
                            animation: true,
                            animateFromLastPercent: true,
                            center: Text(
                              '${(_uploadProgress * 100).toInt()}%',
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                  ),
                ],
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Submitting...',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
              ],
            )
          : Text(
              'Submit Bug Report',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
    );
  }
} 