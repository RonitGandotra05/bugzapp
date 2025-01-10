import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import '../models/bug_report.dart';
import '../services/bug_report_service.dart';
import '../utils/token_storage.dart';
import '../widgets/bug_card.dart';
import '../widgets/app_drawer.dart';
import 'login_screen.dart';
import '../models/bug_filter.dart';
import '../widgets/bug_filter_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import '../models/user.dart';
import '../models/project.dart';
import '../constants/api_constants.dart';
import '../widgets/stats_panel.dart';
import 'dart:convert';
import 'dart:math' show pi;
import 'package:universal_html/html.dart' as html;
import '../widgets/custom_search_bar.dart';
import 'package:http_parser/http_parser.dart';
import '../services/auth_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/notification_bell.dart';
import '../services/notification_service.dart';

enum BugFilter {
  all,
  createdByMe,
  assignedToMe,
}

extension WidgetPaddingX on Widget {
  Widget paddingAll(double padding) => Padding(
        padding: EdgeInsets.all(padding),
        child: this,
      );
}

class HomeScreen extends StatefulWidget {
  final int? initialBugId;
  const HomeScreen({Key? key, this.initialBugId}) : super(key: key);

  @override
  HomeScreenState createState() => HomeScreenState();
}

class BugFilterManager {
  final List<BugReport> allBugs;
  final BugFilter userFilter;
  final BugFilterType statusFilter;
  final User? currentUser;
  final String searchQuery;
  final BugReportService bugReportService;
  final Set<int> selectedProjectIds;

  BugFilterManager({
    required this.allBugs,
    required this.userFilter,
    required this.statusFilter,
    required this.currentUser,
    required this.bugReportService,
    required this.selectedProjectIds,
    this.searchQuery = '',
  });

  List<BugReport> get userFilteredBugs {
    List<BugReport> filtered = allBugs;
    
    // First apply project filter if any projects are selected
    if (selectedProjectIds.isNotEmpty) {
      filtered = filtered.where((bug) => 
        bug.projectId != null && selectedProjectIds.contains(bug.projectId)
      ).toList();
    }
    
    // Then apply user filter
    switch (userFilter) {
      case BugFilter.assignedToMe:
        return filtered.where((bug) => bug.recipientId == currentUser?.id).toList();
      case BugFilter.createdByMe:
        return filtered.where((bug) => bug.creatorId == currentUser?.id).toList();
      case BugFilter.all:
      default:
        return filtered;
    }
  }

  List<BugReport> get filteredByStatus {
    final baseList = userFilteredBugs;
    switch (statusFilter) {
      case BugFilterType.resolved:
        return baseList.where((bug) => bug.status == BugStatus.resolved).toList();
      case BugFilterType.pending:
        return baseList.where((bug) => bug.status == BugStatus.assigned).toList();
      case BugFilterType.all:
      default:
        return baseList;
    }
  }

  List<BugReport> get searchFiltered {
    if (searchQuery.isEmpty) return filteredByStatus;
    
    final searchLower = searchQuery.toLowerCase();
    return filteredByStatus.where((bug) {
      // Get comments directly from cache
      final comments = bugReportService.getCachedComments(bug.id);
      final hasMatchingComment = comments.any((comment) =>
        comment.comment.toLowerCase().contains(searchLower) ||
        comment.userName.toLowerCase().contains(searchLower)
      );

      return bug.description.toLowerCase().contains(searchLower) ||
        (bug.creator?.toLowerCase() ?? '').contains(searchLower) ||
        (bug.recipient?.toLowerCase() ?? '').contains(searchLower) ||
        bug.severityText.toLowerCase().contains(searchLower) ||
        bug.statusText.toLowerCase().contains(searchLower) ||
        (bug.projectName?.toLowerCase() ?? '').contains(searchLower) ||
        hasMatchingComment;  // Include comments in search
    }).toList();
  }

  // Stats calculations
  int get totalBugs => userFilteredBugs.length;
  
  int get resolvedBugs => userFilteredBugs
    .where((bug) => bug.status == BugStatus.resolved)
    .length;
  
  int get pendingBugs => userFilteredBugs
    .where((bug) => bug.status == BugStatus.assigned)
    .length;
}

class HomeScreenState extends State<HomeScreen> {
  final _bugReportService = BugReportService();
  final _searchController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _listViewKey = GlobalKey();
  
  User? _currentUser;
  List<User> _users = [];
  List<Project> _projects = [];
  List<BugReport> _bugReports = [];
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isAscendingOrder = false;
  String _userName = '';
  BugFilter _currentBugFilter = BugFilter.all;
  BugFilterType _currentFilter = BugFilterType.all;
  
  // Add missing variables for bug report form
  String? _description;
  User? _selectedRecipient;
  File? _imageFile;
  Uint8List? _webImageBytes;
  String _selectedSeverity = 'low';
  Project? _selectedProject;
  String? _tabUrl;
  List<User> _availableUsers = [];
  List<Project> _availableProjects = [];
  bool _isSubmitting = false;
  List<String> _selectedCCRecipients = [];
  File? _selectedFile;

  late BugFilterManager _filterManager;

  // Add new state variables
  Set<int> _selectedProjectIds = {};
  bool _showProjectFilter = false;

  // Add these variables for caching
  File? _cachedImageFile;
  Uint8List? _cachedWebImageBytes;

  int? _highlightedBugId;

  Set<int> _selectedBugIds = {};
  bool get _isSelectionMode => _selectedBugIds.isNotEmpty;

  String? _error;

  final Map<int, GlobalKey> _bugCardKeys = {};

  @override
  void initState() {
    super.initState();
    _filterManager = BugFilterManager(
      allBugs: [],
      userFilter: _currentBugFilter,
      statusFilter: _currentFilter,
      currentUser: null,
      bugReportService: _bugReportService,
      selectedProjectIds: _selectedProjectIds,
    );
    _loadData();
    _setupRealTimeUpdates();
    
    // Handle initial bug ID if provided
    if (widget.initialBugId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToBugCard(widget.initialBugId!);
      });
    }
  }

  void _setupRealTimeUpdates() {
    // Listen for bug report updates
    _bugReportService.bugReportStream.listen(
      (bugReport) {
        if (mounted) {
          setState(() {
            final index = _bugReports.indexWhere((b) => b.id == bugReport.id);
            if (index != -1) {
              // Update existing bug report
              _bugReports[index] = bugReport;
              print('Updated existing bug report #${bugReport.id}');
            } else {
              // Add new bug report
              _bugReports.insert(0, bugReport);
              print('Added new bug report #${bugReport.id}');
              
              // Only show notification for new bug reports and if not created by current user
              if (_currentUser?.id != bugReport.creatorId) {
                NotificationService().showBugNotification(
                  title: 'New Bug Report #${bugReport.id}',
                  body: '${bugReport.creator ?? "Someone"} reported: ${bugReport.description}',
                  bugId: bugReport.id.toString(),
                  creatorName: bugReport.creator,
                  isInApp: true,
                );
              }
            }
            
            // Sort the list to maintain order
            _bugReports.sort((a, b) => 
              _isAscendingOrder ? a.id.compareTo(b.id) : b.id.compareTo(a.id)
            );
            
            // Update filter manager
            _updateFilterManager();
          });
        }
      },
      onError: (error) {
        print('Error in bug report stream: $error');
      },
    );

    // Refresh bug reports periodically to ensure sync
    Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        _refreshBugReports();
      }
    });
  }

  void _updateFilterManager() {
    _filterManager = BugFilterManager(
      allBugs: List.from(_bugReports),
      userFilter: _currentBugFilter,
      statusFilter: _currentFilter,
      currentUser: _currentUser,
      bugReportService: _bugReportService,
      selectedProjectIds: _selectedProjectIds,
      searchQuery: _searchQuery,
    );
  }

  List<BugReport> get _filteredBugReports {
    _updateFilterManager();
    return _filterManager.searchFiltered;
  }

  List<BugReport> get _sortedAndFilteredBugReports {
    final filtered = _filteredBugReports;
    return List.from(filtered)..sort((a, b) => _isAscendingOrder 
      ? a.modifiedDate.compareTo(b.modifiedDate)
      : b.modifiedDate.compareTo(a.modifiedDate));
  }

  // Update stats methods to use filter manager
  int _getTotalBugs() {
    _updateFilterManager();
    return _filterManager.totalBugs;
  }

  int _getResolvedBugs() {
    _updateFilterManager();
    return _filterManager.resolvedBugs;
  }

  int _getPendingBugs() {
    _updateFilterManager();
    return _filterManager.pendingBugs;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final currentUser = await _bugReportService.getCurrentUser();
      final users = await _bugReportService.fetchUsers();
      final projects = await _bugReportService.fetchProjects();
      final bugReports = await _bugReportService.getAllBugReports();
      
      // Load all comments at once
      await _bugReportService.loadAllComments();
      
      if (mounted) {
        setState(() {
          _currentUser = currentUser;
          _userName = currentUser?.name ?? '';
          _users = users;
          _availableUsers = users;
          _projects = projects;
          _bugReports = bugReports;
          _isLoading = false;
          
          // Update filter manager with fresh data
          _updateFilterManager();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  List<int> _getVisibleBugIds() {
    final visibleBugs = _sortedAndFilteredBugReports.take(10).toList();
    return visibleBugs.map((bug) => bug.id).toList();
  }

  void _handleStatusFilterChange(BugFilterType filter) {
    setState(() {
      _currentFilter = filter;
      // Update filter manager with existing data
      _updateFilterManager();
    });
  }

  void _handleUserFilterChange(BugFilter filter) {
    setState(() {
      _currentBugFilter = filter;
      // Update filter manager with existing data
      _updateFilterManager();
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _isAscendingOrder = !_isAscendingOrder;
      // No need to reload data, just update UI with cached data
    });
  }

  Future<void> _deleteBugReport(int bugId) async {
    try {
      await _bugReportService.deleteBugReport(bugId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bug report deleted successfully')),
      );
      _loadData(); // Refresh the list
    } catch (e) {
      print('Error deleting bug report: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting bug report: $e')),
      );
    }
  }

  Future<void> _sendReminder(int bugId) async {
    try {
      final response = await _bugReportService.sendReminder(bugId);
      
      // Show success message with details
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reminder sent successfully'),
                if (response['notifications_sent']?.isNotEmpty ?? false)
                  Text(
                    'Sent to: ${(response['notifications_sent'] as List).join(", ")}',
                    style: const TextStyle(fontSize: 12),
                  ),
                if (response['failed_notifications']?.isNotEmpty ?? false)
                  Text(
                    'Failed to send to some recipients',
                    style: const TextStyle(color: Colors.yellow),
                  ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending reminder: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadBugReport() async {
    if (_description == null || _description!.isEmpty) {
      setState(() => _error = 'Description is required');
      return;
    }

    if (_selectedRecipient == null) {
      setState(() => _error = 'Please select a recipient');
      return;
    }

    if (_imageFile == null && _webImageBytes == null && 
        _cachedImageFile == null && _cachedWebImageBytes == null) {
      setState(() => _error = 'Please select or capture an image');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // Use cached image if main image is null
      final imageFileToUpload = _imageFile ?? _cachedImageFile;
      final imageBytesToUpload = _webImageBytes ?? _cachedWebImageBytes;
      
      await _bugReportService.uploadBugReport(
        description: _description!,
        recipientId: _selectedRecipient!.id.toString(),
        imageFile: imageFileToUpload,
        imageBytes: imageBytesToUpload,
        severity: _selectedSeverity.toLowerCase(),
        projectId: _selectedProject?.id.toString(),
        tabUrl: _tabUrl,
        ccRecipients: _selectedCCRecipients,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bug report uploaded successfully')),
        );
        _resetForm();
        _loadBugReports();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading bug report: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _takePicture() async {
    if (kIsWeb) {
      await _pickImage(ImageSource.camera);
      return;
    }

    try {
      // Check camera permission
      final status = await Permission.camera.status;
      if (status.isDenied || status.isRestricted) {
        // Request permission directly without showing dialog first
        final result = await Permission.camera.request();
        
        if (result.isDenied || result.isPermanentlyDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result.isPermanentlyDenied
                      ? 'Camera permission is required. Please enable it in app settings.'
                      : 'Camera permission is required to take photos',
                ),
                backgroundColor: Colors.red,
                action: result.isPermanentlyDenied
                    ? SnackBarAction(
                        label: 'Settings',
                        onPressed: () => openAppSettings(),
                        textColor: Colors.white,
                      )
                    : null,
              ),
            );
          }
          return;
        }
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Camera permission is required. Please enable it in app settings.'),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => openAppSettings(),
                textColor: Colors.white,
              ),
            ),
          );
        }
        return;
      }

      // Now that we have permission, take the picture
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
        preferredCameraDevice: CameraDevice.rear,
      );
      
      if (photo != null) {
        // Process image in a separate isolate if possible
        try {
          final file = File(photo.path);
          if (mounted) {
            setState(() {
              _imageFile = file;
              _selectedFile = file;
              _cachedImageFile = file;
              _webImageBytes = null;
              _cachedWebImageBytes = null;
            });
          }
        } catch (e) {
          print('Error processing image: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error processing photo: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error taking picture: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      
      if (photo != null && mounted) {
        try {
          if (kIsWeb) {
            final bytes = await photo.readAsBytes();
            if (mounted) {
              setState(() {
                _webImageBytes = bytes;
                _cachedWebImageBytes = bytes;
                _imageFile = null;
                _selectedFile = null;
                _cachedImageFile = null;
              });
            }
          } else {
            final file = File(photo.path);
            if (mounted) {
              setState(() {
                _imageFile = file;
                _selectedFile = file;
                _cachedImageFile = file;
                _webImageBytes = null;
                _cachedWebImageBytes = null;
              });
            }
          }
        } catch (e) {
          print('Error processing selected image: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error processing selected image: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildStatsPanel() {
    return StatsPanel(
      userName: _userName.capitalize(),  // Use the stored user name
      totalBugs: _getTotalBugs(),
      resolvedBugs: _getResolvedBugs(),
      pendingBugs: _getPendingBugs(),
      onFilterChange: _handleStatusFilterChange,
      currentFilter: _currentFilter,
    );
  }

  Future<void> _refreshEverything() async {
    setState(() {
      _isLoading = true;
      _error = null; // Reset error state
    });
    try {
      // Clear all caches and reinitialize everything
      await _bugReportService.refreshEverything();
      
      // Reload all data
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refreshed successfully'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error during refresh: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Add this method to show project filter dialog
  void _showProjectFilterDialog() {
    bool isApplying = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'Filter by Projects',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Container(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                // Select All/None row
                Row(
                  children: [
                    TextButton.icon(
                      icon: Icon(Icons.select_all, color: Colors.purple[400]),
                      label: Text(
                        'Select All',
                        style: GoogleFonts.poppins(color: Colors.purple[400]),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedProjectIds = Set.from(_projects.map((p) => p.id));
                          _updateFilterManager(); // Update filter manager immediately
                        });
                      },
                    ),
                    const Spacer(),
                    TextButton.icon(
                      icon: Icon(Icons.clear_all, color: Colors.grey[600]),
                      label: Text(
                        'Clear All',
                        style: GoogleFonts.poppins(color: Colors.grey[600]),
                      ),
                      onPressed: () {
                        setState(() {
                          _selectedProjectIds.clear();
                          _updateFilterManager(); // Update filter manager immediately
                        });
                      },
                    ),
                  ],
                ),
                const Divider(),
                ..._projects.map((project) {
                  return Material(
                    color: Colors.transparent,
                    child: CheckboxListTile(
                      title: Text(
                        project.name,
                        style: GoogleFonts.poppins(),
                      ),
                      value: _selectedProjectIds.contains(project.id),
                      activeColor: Colors.purple[400],
                      onChanged: (bool? value) {
                        setState(() {
                          if (value == true) {
                            _selectedProjectIds.add(project.id);
                          } else {
                            _selectedProjectIds.remove(project.id);
                          }
                          _updateFilterManager(); // Update filter manager immediately
                        });
                      },
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isApplying ? null : () {
                // Reset to previous state if cancelled
                this.setState(() {
                  _updateFilterManager();
                });
                Navigator.pop(context);
              },
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              onPressed: isApplying ? null : () async {
                setState(() => isApplying = true);
                
                // Add a small delay to show the loading state
                await Future.delayed(const Duration(milliseconds: 300));
                
                this.setState(() {
                  _updateFilterManager();
                });
                
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple[400],
                minimumSize: const Size(80, 36),
              ),
              child: isApplying
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Apply',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // Update the filter button in the build method
  Widget _buildFilterButton() {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: PopupMenuButton<String>(
          padding: EdgeInsets.zero,
          icon: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(
                  Icons.filter_list,
                  size: 24,
                  color: Colors.purple[400],
                ),
              ),
              if (_selectedProjectIds.isNotEmpty)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.purple[400],
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _selectedProjectIds.length.toString(),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          onSelected: (String value) {
            switch (value) {
              case 'all':
                _handleUserFilterChange(BugFilter.all);
                break;
              case 'created':
                _handleUserFilterChange(BugFilter.createdByMe);
                break;
              case 'assigned':
                _handleUserFilterChange(BugFilter.assignedToMe);
                break;
              case 'projects':
                _showProjectFilterDialog();
                break;
            }
          },
          itemBuilder: (BuildContext context) => [
            PopupMenuItem(
              value: 'all',
              child: Row(
                children: [
                  Icon(
                    Icons.all_inbox,
                    color: _currentBugFilter == BugFilter.all
                        ? Colors.purple[400]
                        : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'All Bugs',
                    style: TextStyle(
                      color: _currentBugFilter == BugFilter.all
                          ? Colors.purple[400]
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'created',
              child: Row(
                children: [
                  Icon(
                    Icons.create,
                    color: _currentBugFilter == BugFilter.createdByMe
                        ? Colors.purple[400]
                        : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Created by Me',
                    style: TextStyle(
                      color: _currentBugFilter == BugFilter.createdByMe
                          ? Colors.purple[400]
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'assigned',
              child: Row(
                children: [
                  Icon(
                    Icons.assignment_ind,
                    color: _currentBugFilter == BugFilter.assignedToMe
                        ? Colors.purple[400]
                        : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Assigned to Me',
                    style: TextStyle(
                      color: _currentBugFilter == BugFilter.assignedToMe
                          ? Colors.purple[400]
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'projects',
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    color: _selectedProjectIds.isNotEmpty
                        ? Colors.purple[400]
                        : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Filter by Projects',
                    style: TextStyle(
                      color: _selectedProjectIds.isNotEmpty
                          ? Colors.purple[400]
                          : Colors.grey[600],
                    ),
                  ),
                  if (_selectedProjectIds.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _selectedProjectIds.length.toString(),
                        style: TextStyle(
                          color: Colors.purple[700],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void scrollToBugCard(int bugId) {
    setState(() {
      _highlightedBugId = bugId;
    });

    // Wait for the next frame to ensure the ListView is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_bugCardKeys[bugId]?.currentContext != null) {
        Scrollable.ensureVisible(
          _bugCardKeys[bugId]!.currentContext!,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
        
        // Add a delayed removal of highlight
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _highlightedBugId = null;
            });
          }
        });
      }
    });
  }

  void _toggleBugSelection(BugReport bug, bool selected) {
    setState(() {
      if (selected) {
        _selectedBugIds.add(bug.id);
      } else {
        _selectedBugIds.remove(bug.id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedBugIds.clear();
    });
  }

  Future<void> _handleMultipleDelete() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Bug Reports'),
        content: Text('Are you sure you want to delete ${_selectedBugIds.length} bug reports?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      try {
        for (final bugId in _selectedBugIds) {
          await _bugReportService.deleteBugReport(bugId);
        }
        _clearSelection();
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Bug reports deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting bug reports: $e')),
          );
        }
      }
    }
  }

  Future<void> _handleMultipleStatusToggle() async {
    final selectedBugs = _bugReports.where((bug) => _selectedBugIds.contains(bug.id)).toList();
    final allResolved = selectedBugs.every((bug) => bug.status == BugStatus.resolved);
    final allPending = selectedBugs.every((bug) => bug.status == BugStatus.assigned);

    if (!allResolved && !allPending) return; // Mixed status, don't show toggle option

    final newStatus = allResolved ? 'pending' : 'resolved';
    final shouldToggle = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Change Status'),
        content: Text('Mark ${_selectedBugIds.length} bugs as $newStatus?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirm'),
          ),
        ],
      ),
    );

    if (shouldToggle == true) {
      try {
        for (final bugId in _selectedBugIds) {
          await _bugReportService.toggleBugStatus(bugId);
        }
        _clearSelection();
        _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Bug reports updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating bug reports: $e')),
          );
        }
      }
    }
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    final selectedBugs = _bugReports.where((bug) => _selectedBugIds.contains(bug.id)).toList();
    final allResolved = selectedBugs.every((bug) => bug.status == BugStatus.resolved);
    final allPending = selectedBugs.every((bug) => bug.status == BugStatus.assigned);

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.close),
        onPressed: _clearSelection,
        color: Colors.black87,
      ),
      title: Text(
        '${_selectedBugIds.length} selected',
        style: TextStyle(color: Colors.black87),
      ),
      actions: [
        if (allResolved || allPending)
          IconButton(
            icon: Icon(
              allResolved ? Icons.refresh : Icons.check_circle_outline,
              color: allResolved ? Colors.orange : Colors.green,
            ),
            onPressed: _handleMultipleStatusToggle,
            tooltip: allResolved ? 'Mark as Pending' : 'Mark as Resolved',
          ),
        IconButton(
          icon: Icon(Icons.delete_outline, color: Colors.red),
          onPressed: _handleMultipleDelete,
          tooltip: 'Delete Selected',
        ),
      ],
    );
  }

  // Add error display widget
  Widget _buildErrorDisplay() {
    if (_error == null) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: GoogleFonts.poppins(
                color: Colors.red[700],
                fontSize: 14,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _error = null),
            color: Colors.red[700],
          ),
        ],
      ),
    );
  }

  // Add refresh method
  Future<void> _refreshBugReports() async {
    try {
      await _bugReportService.refreshBugReports();
      if (mounted) {
        setState(() {
          // Update bug reports from the service's cache
          _bugReports = _bugReportService.getCachedBugReports();
          // Update filter manager
          _updateFilterManager();
        });
      }
    } catch (e) {
      print('Error refreshing bug reports: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing bug reports: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: _isSelectionMode ? _buildSelectionAppBar() : AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.menu,
            color: Colors.black87,
          ),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
        centerTitle: true,
        title: const Icon(
          Icons.bug_report,
          color: Colors.black87,
          size: 28,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          NotificationBell(
            bugReportStream: _bugReportService.bugReportStream,
            commentStream: _bugReportService.commentStream,
            onBugTap: scrollToBugCard,
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: AppDrawer(
        onLogout: _handleLogout,
        userName: _userName,
        isAdmin: _currentUser?.isAdmin ?? false,
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refreshEverything,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // Welcome Message
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.purple[300]!,
                          Colors.purple[400]!,
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome Back, ${_userName ?? ""}',
                          style: GoogleFonts.poppins(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You have ${_getPendingBugs()} pending reports to resolve.',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Stats Panel
                SliverToBoxAdapter(
                  child: _buildStatsPanel(),
                ),
                // Search Bar
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    child: CustomSearchBar(
                      controller: _searchController,
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                      },
                      onClear: () {
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      hintText: 'Search by description, creator, or project...',
                    ),
                  ),
                ),
                // Filter Chips
                SliverToBoxAdapter(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _buildFilterButton(),
                        // Sort Button
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _toggleSortOrder,
                              customBorder: const CircleBorder(),
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Icon(
                                  _isAscendingOrder 
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  size: 24,
                                  color: Colors.purple[400],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Bug List
                SliverToBoxAdapter(
                  child: Container(
                    key: _listViewKey,
                    color: const Color(0xFFFAF9F6),
                    child: Column(
                      children: [
                        if (_isLoading)
                          const Center(child: CircularProgressIndicator())
                        else if (_sortedAndFilteredBugReports.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                'No bug reports found',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _sortedAndFilteredBugReports.length,
                            itemBuilder: (context, index) {
                              final bug = _sortedAndFilteredBugReports[index];
                              // Ensure we have a key for this bug card
                              _bugCardKeys[bug.id] = _bugCardKeys[bug.id] ?? GlobalKey();
                              return BugCard(
                                key: _bugCardKeys[bug.id],
                                bug: bug,
                                onStatusToggle: () => _toggleBugStatus(bug.id),
                                onDelete: () => _deleteBugReport(bug.id),
                                onSendReminder: () => _sendReminder(bug.id),
                                bugReportService: _bugReportService,
                                highlight: bug.id == _highlightedBugId,
                                isSelected: _selectedBugIds.contains(bug.id),
                                onSelectionChanged: (selected) => _toggleBugSelection(bug, selected),
                                selectionMode: _selectedBugIds.isNotEmpty,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Scroll to top button
          AnimatedBuilder(
            animation: _scrollController,
            builder: (context, child) {
              final showButton = _scrollController.hasClients && 
                               _scrollController.offset > 300;
              return AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                left: 16,
                bottom: showButton ? 16 : -60,
                child: FloatingActionButton(
                  heroTag: 'scrollToTopButton',
                  onPressed: () {
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeInOut,
                    );
                  },
                  backgroundColor: Colors.purple[400],
                  elevation: 4,
                  child: const Icon(
                    Icons.arrow_upward,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'addBugButton',
        onPressed: () => _showAddBugReport(context),
        backgroundColor: Colors.purple[400],
        elevation: 4,
        child: const Icon(
          Icons.add,
          color: Colors.white,
        ),
      ),
    );
  }

  Future<void> _toggleBugStatus(int bugId) async {
    try {
      await _bugReportService.toggleBugStatus(bugId);
      _loadData(); // Reload data after toggle
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error toggling status: $e')),
      );
    }
  }

  Future<void> _handleLogout() async {
    try {
      await AuthService().logout();  // This will clear all caches properly
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during logout: $e')),
        );
      }
    }
  }

  Future<void> _showAddBugReport(BuildContext context) async {
    final _formKey = GlobalKey<FormState>();
    String? _description;
    String? _selectedProjectId;
    String? _selectedRecipientId;
    String? _tabUrl;
    bool _isSubmitting = false;
    String _selectedSeverity = 'low';
    List<String> _selectedCCRecipients = [];
    File? _selectedFile;

    // Restore cached images instead of resetting
    setState(() {
      _imageFile = _cachedImageFile;
      _webImageBytes = _cachedWebImageBytes;
      _selectedFile = _cachedImageFile;
      _selectedSeverity = 'low';
      _selectedCCRecipients = [];
    });

    // Ensure data is loaded
    if (_users.isEmpty || _projects.isEmpty) {
      await _loadData();
    }

    // Create a StatefulBuilder to manage dialog state
    await showDialog(
      context: context,
      barrierDismissible: false,  // Prevent dismissing by tapping outside
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => WillPopScope(
          onWillPop: () async {
            // Show confirmation dialog if form has data
            if (_description != null || _selectedProjectId != null || 
                _selectedRecipientId != null || _imageFile != null || 
                _webImageBytes != null || _cachedImageFile != null || 
                _cachedWebImageBytes != null) {
              final shouldPop = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(
                    'Discard Changes?',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  content: Text(
                    'Are you sure you want to discard your changes?',
                    style: GoogleFonts.poppins(),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(color: Colors.grey[600]),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context, true);
                        _resetForm();
                      },
                      child: Text(
                        'Discard',
                        style: GoogleFonts.poppins(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
              return shouldPop ?? false;
            }
            return true;
          },
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header with close button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Add Bug Report',
                            style: GoogleFonts.poppins(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () async {
                              // Show confirmation if form has data
                              if (_description != null || _selectedProjectId != null || 
                                  _selectedRecipientId != null || _imageFile != null || 
                                  _webImageBytes != null || _cachedImageFile != null || 
                                  _cachedWebImageBytes != null) {
                                final shouldClose = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(
                                      'Discard Changes?',
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                                    ),
                                    content: Text(
                                      'Are you sure you want to discard your changes?',
                                      style: GoogleFonts.poppins(),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        child: Text(
                                          'Cancel',
                                          style: GoogleFonts.poppins(color: Colors.grey[600]),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context, true);
                                          _resetForm();
                                        },
                                        child: Text(
                                          'Discard',
                                          style: GoogleFonts.poppins(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (shouldClose ?? false) {
                                  Navigator.pop(context);
                                }
                              } else {
                                Navigator.pop(context);
                              }
                            },
                            color: Colors.grey[600],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Description TextField
                      TextFormField(
                        decoration: InputDecoration(
                          labelText: 'Description',
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
                        maxLines: 3,
                        onChanged: (value) => _description = value,
                        validator: (value) => value?.isEmpty ?? true ? 'Description is required' : null,
                      ),
                      const SizedBox(height: 20),

                      // Project Dropdown
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Project',
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
                          setState(() {
                            _selectedProjectId = value;
                          });
                        },
                        validator: (value) => value == null ? 'Please select a project' : null,
                      ),
                      const SizedBox(height: 20),

                      // Recipient Dropdown
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Recipient',
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
                        items: _users.map((user) {
                          return DropdownMenuItem(
                            value: user.id.toString(),
                            child: Text(user.name),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedRecipientId = value;
                          });
                        },
                        validator: (value) => value == null ? 'Please select a recipient' : null,
                      ),
                      const SizedBox(height: 20),

                      // CC Recipients Section
                      Text(
                        'CC Recipients (Optional)',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 8),
                      
                      // CC Recipients Chips and Add Button
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // Existing CC Recipients as Chips
                          ..._selectedCCRecipients.where((r) => r.isNotEmpty).map((recipient) {
                            return Chip(
                              label: Text(
                                recipient,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: Colors.grey[800],
                                ),
                              ),
                              backgroundColor: Colors.white,
                              deleteIcon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.grey[600],
                              ),
                              onDeleted: () {
                                setState(() {
                                  _selectedCCRecipients.remove(recipient);
                                });
                              },
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(color: Colors.grey[300]!),
                              ),
                            );
                          }).toList(),
                          
                          // Add CC Recipient Button (only show if less than 4 recipients)
                          if (_selectedCCRecipients.where((r) => r.isNotEmpty).length < 4)
                            InkWell(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(
                                      'Add CC Recipient',
                                      style: GoogleFonts.poppins(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    content: DropdownButtonFormField<String>(
                                      decoration: InputDecoration(
                                        labelText: 'Select User',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey[50],
                                      ),
                                      items: _users
                                          .where((user) =>
                                              user.id.toString() != _selectedRecipientId &&
                                              !_selectedCCRecipients.contains(user.name))
                                          .map((user) {
                                        return DropdownMenuItem(
                                          value: user.name,
                                          child: Text(user.name),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        if (value != null) {
                                          setState(() {
                                            _selectedCCRecipients.add(value);
                                          });
                                          Navigator.pop(context);
                                        }
                                      },
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(
                                          'Cancel',
                                          style: GoogleFonts.poppins(
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.purple[300]!),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_rounded,
                                      size: 18,
                                      color: Colors.purple[400],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Add CC',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: Colors.purple[400],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Severity Dropdown
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: 'Severity',
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
                        items: [
                          {'display': 'Low', 'value': 'low'},
                          {'display': 'Medium', 'value': 'medium'},
                          {'display': 'High', 'value': 'high'},
                        ].map((severity) {
                          return DropdownMenuItem(
                            value: severity['value'],
                            child: Text(
                              severity['display']!,
                              style: GoogleFonts.poppins(),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedSeverity = value ?? 'low';
                          });
                        },
                      ),
                      const SizedBox(height: 20),

                      // Tab URL TextField
                      TextFormField(
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
                        onChanged: (value) => _tabUrl = value,
                      ),
                      const SizedBox(height: 20),

                      // Image Upload Section
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.white,
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  // Take Photo Button
                                  Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () async {
                                          await _takePicture();
                                          setState(() {});  // Refresh the state after taking picture
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.camera_alt_rounded,
                                                size: 32,
                                                color: Colors.purple[400],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Take Photo',
                                                style: GoogleFonts.poppins(
                                                  color: Colors.grey[700],
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Vertical Divider
                                  Container(
                                    height: 40,
                                    width: 1,
                                    color: Colors.grey[300],
                                  ),
                                  // Choose from Gallery Button
                                  Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () async {
                                          await _pickImage(ImageSource.gallery);
                                          setState(() {});  // Refresh the state after picking image
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.photo_library_rounded,
                                                size: 32,
                                                color: Colors.purple[400],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Gallery',
                                                style: GoogleFonts.poppins(
                                                  color: Colors.grey[700],
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Image Preview Section - Updated condition
                            if (_imageFile != null || _webImageBytes != null || _cachedImageFile != null || _cachedWebImageBytes != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Image Preview Header
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle_rounded,
                                          color: Colors.green[400],
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Image Preview',
                                            style: GoogleFonts.poppins(
                                              color: Colors.grey[700],
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.close_rounded,
                                            color: Colors.grey[600],
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _imageFile = null;
                                              _webImageBytes = null;
                                              _cachedImageFile = null;
                                              _cachedWebImageBytes = null;
                                              _selectedFile = null;
                                            });
                                          },
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          iconSize: 20,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Image Preview Container
                                    Container(
                                      height: 200,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey[300]!),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: kIsWeb
                                          ? (_webImageBytes ?? _cachedWebImageBytes) != null
                                              ? Image.memory(
                                                  _webImageBytes ?? _cachedWebImageBytes!,
                                                  fit: BoxFit.contain,
                                                )
                                              : const SizedBox()
                                          : (_imageFile ?? _cachedImageFile) != null
                                              ? Image.file(
                                                  _imageFile ?? _cachedImageFile!,
                                                  fit: BoxFit.contain,
                                                )
                                              : const SizedBox(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Submit Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isSubmitting
                              ? null
                              : () async {
                                  if (_formKey.currentState?.validate() ?? false) {
                                    // Check for required fields before submission
                                    if (_description == null || _description!.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Description is required')),
                                      );
                                      return;
                                    }

                                    if (_selectedRecipientId == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please select a recipient')),
                                      );
                                      return;
                                    }

                                    if (_imageFile == null && _webImageBytes == null && 
                                        _cachedImageFile == null && _cachedWebImageBytes == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please select or capture an image')),
                                      );
                                      return;
                                    }

                                    setState(() => _isSubmitting = true);
                                    try {
                                      await _bugReportService.uploadBugReport(
                                        description: _description!,
                                        recipientId: _selectedRecipientId!,
                                        ccRecipients: _selectedCCRecipients.where((r) => r.isNotEmpty).toList(),
                                        imageFile: _imageFile ?? _cachedImageFile,
                                        imageBytes: _webImageBytes ?? _cachedWebImageBytes,
                                        severity: _selectedSeverity,
                                        projectId: _selectedProjectId,
                                        tabUrl: _tabUrl ?? '',
                                      );
                                      
                                      if (mounted) {
                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Bug report created successfully')),
                                        );
                                        _loadData();
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Error creating bug report: $e')),
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() => _isSubmitting = false);
                                      }
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple[400],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: _isSubmitting
                              ? const CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                )
                              : Text(
                                  'Submit',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
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
      ),
    );
  }

  void _resetForm() {
    setState(() {
      _description = null;
      _selectedRecipient = null;
      _imageFile = null;
      _webImageBytes = null;
      _cachedImageFile = null;  // Clear cached image
      _cachedWebImageBytes = null;  // Clear cached web image
      _selectedSeverity = 'low';
      _selectedProject = null;
      _tabUrl = null;
      _selectedCCRecipients = [];
    });
  }

  Future<void> _loadBugReports() async {
    try {
      final reports = await _bugReportService.getAllBugReports();
      if (mounted) {
        setState(() {
          _bugReports = reports;
        });
      }
    } catch (e) {
      print('Error loading bug reports: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading bug reports: $e')),
        );
      }
    }
  }

  Future<void> _loadComments(List<int> bugIds) async {
    try {
      await _bugReportService.preloadComments(bugIds);
    } catch (e) {
      print('Error preloading comments: $e');
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1)}";
  }
} 