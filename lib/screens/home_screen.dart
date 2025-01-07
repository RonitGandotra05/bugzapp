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
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
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

class _HomeScreenState extends State<HomeScreen> {
  final _bugReportService = BugReportService();
  final _searchController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _formKey = GlobalKey<FormState>();
  
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
  }

  void _setupRealTimeUpdates() {
    // Listen for bug report updates
    _bugReportService.bugReportStream.listen((bugReport) {
      if (mounted) {
        setState(() {
          print('Received bug report update: ${bugReport.id} - ${bugReport.description}');
          
          // Update or add the bug report in the list
          final index = _bugReports.indexWhere((b) => b.id == bugReport.id);
          if (index != -1) {
            _bugReports[index] = bugReport;
            print('Updated existing bug report at index $index');
          } else {
            _bugReports.add(bugReport);
            print('Added new bug report to list');
          }
          
          // Sort the list to maintain order
          _bugReports.sort((a, b) => 
            _isAscendingOrder ? a.id.compareTo(b.id) : b.id.compareTo(a.id)
          );
          
          // Update filter manager
          _updateFilterManager();
          
          print('Current bug reports count: ${_bugReports.length}');
          print('Filtered bug reports count: ${_filterManager.searchFiltered.length}');
        });
      }
    });

    // Listen for comment updates
    _bugReportService.commentStream.listen((comment) {
      if (mounted) {
        setState(() {
          print('Received comment update for bug ${comment.bugReportId}');
        });
      }
    });

    // Listen for project updates
    _bugReportService.projectStream.listen((project) {
      if (mounted) {
        setState(() {
          final index = _projects.indexWhere((p) => p.id == project.id);
          if (index != -1) {
            _projects[index] = project;
          } else {
            _projects.add(project);
          }
          _availableProjects = _projects; // Update available projects for bug creation
        });
      }
    });

    // Listen for user updates
    _bugReportService.userStream.listen((user) {
      if (mounted) {
        setState(() {
          final index = _users.indexWhere((u) => u.id == user.id);
          if (index != -1) {
            _users[index] = user;
          } else {
            _users.add(user);
          }
          _availableUsers = _users; // Update available users for bug assignment
          
          // Update current user if it's the same user
          if (_currentUser?.id == user.id) {
            _currentUser = user;
          }
        });
      }
    });
  }

  void _updateFilterManager() {
    _filterManager = BugFilterManager(
      allBugs: _bugReports,
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
    setState(() => _isLoading = true);
    try {
      final currentUser = await _bugReportService.getCurrentUser();
      final users = await _bugReportService.fetchUsers();
      final projects = await _bugReportService.fetchProjects();
      final bugReports = await _bugReportService.getAllBugReports();

      if (mounted) {
        setState(() {
          _currentUser = currentUser;
          _userName = currentUser?.name ?? 'User';  // Set the user name
          _users = users;
          _projects = projects;
          _bugReports = bugReports;
          _bugReports.sort((a, b) => 
            _isAscendingOrder ? a.id.compareTo(b.id) : b.id.compareTo(a.id)
          );
          _isLoading = false;
          _updateFilterManager();
        });
      }
    } catch (e) {
      print('Error loading data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
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
    });
  }

  void _handleUserFilterChange(BugFilter filter) {
    setState(() {
      _currentBugFilter = filter;
    });
    _loadData(); // Reload data with new filter
  }

  void _toggleSortOrder() {
    setState(() {
      _isAscendingOrder = !_isAscendingOrder;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Description is required')),
      );
      return;
    }

    if (_selectedRecipient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a recipient')),
      );
      return;
    }

    if (_imageFile == null && _webImageBytes == null && _cachedImageFile == null && _cachedWebImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or capture an image')),
      );
      return;
    }

    try {
      setState(() => _isSubmitting = true);
      
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
      // On web, directly use image picker as it will fall back to file picker
      await _pickImage(ImageSource.camera);
      return;
    }

    try {
      // Check camera permission
      final status = await Permission.camera.status;
      if (status.isDenied) {
        // Request permission
        final result = await Permission.camera.request();
        if (result.isDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Camera permission is required to take photos'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1080,
      );
      
      if (photo != null && mounted) {
        final file = File(photo.path);
        setState(() {
          _imageFile = file;
          _selectedFile = file;
          _cachedImageFile = file;
          _webImageBytes = null;
          _cachedWebImageBytes = null;
        });
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
        if (kIsWeb) {
          final bytes = await photo.readAsBytes();
          setState(() {
            _webImageBytes = bytes;
            _cachedWebImageBytes = bytes;
            _imageFile = null;
            _selectedFile = null;
            _cachedImageFile = null;
          });
        } else {
          final file = File(photo.path);
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
    setState(() => _isLoading = true);
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
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
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
                              _selectedProjectIds = _projects.map((p) => p.id).toSet();
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
                            });
                          },
                        ),
                      ],
                    ),
                    const Divider(),
                    ..._projects.map((project) {
                      return CheckboxListTile(
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
                          });
                        },
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(color: Colors.grey[600]),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    this.setState(() {
                      // Update the main state
                      _updateFilterManager();
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple[400],
                  ),
                  child: Text(
                    'Apply',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
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
          const SizedBox(width: 48),
        ],
      ),
      drawer: AppDrawer(
        isAdmin: _currentUser?.isAdmin ?? false,
        onLogout: _handleLogout,
      ),
      body: RefreshIndicator(
        onRefresh: _refreshEverything,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF9575CD),
                const Color(0xFF7E57C2),
                const Color(0xFF673AB7),
              ],
            ),
          ),
          child: CustomScrollView(
            slivers: [
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
                            return BugCard(
                              bug: bug,
                              onStatusToggle: () => _toggleBugStatus(bug.id),
                              onDelete: () => _deleteBugReport(bug.id),
                              onSendReminder: () => _sendReminder(bug.id),
                              bugReportService: _bugReportService,
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
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddBugReport(context),
        child: const Icon(Icons.add),
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