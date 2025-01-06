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

  BugFilterManager({
    required this.allBugs,
    required this.userFilter,
    required this.statusFilter,
    required this.currentUser,
    required this.bugReportService,
    this.searchQuery = '',
  });

  List<BugReport> get userFilteredBugs {
    switch (userFilter) {
      case BugFilter.assignedToMe:
        return allBugs.where((bug) => bug.recipientId == currentUser?.id).toList();
      case BugFilter.createdByMe:
        return allBugs.where((bug) => bug.creatorId == currentUser?.id).toList();
      case BugFilter.all:
      default:
        return allBugs;
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

  late BugFilterManager _filterManager;

  @override
  void initState() {
    super.initState();
    _filterManager = BugFilterManager(
      allBugs: [],
      userFilter: _currentBugFilter,
      statusFilter: _currentFilter,
      currentUser: null,
      bugReportService: _bugReportService,
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
    if (_description == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Description is required')),
      );
      return;
    }

    try {
      await _bugReportService.uploadBugReport(
        description: _description!,
        recipientId: _selectedRecipient!.id.toString(),
        imageFile: _imageFile,
        imageBytes: _webImageBytes,
        severity: _selectedSeverity.toLowerCase(),
        projectId: _selectedProject?.id.toString(),
        tabUrl: _tabUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bug report uploaded successfully')),
        );
        _resetForm();
        _loadBugReports();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading bug report: $e')),
        );
      }
    }
  }

  Future<void> _takePicture() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);
      
      if (photo != null) {
        if (kIsWeb) {
          final bytes = await photo.readAsBytes();
          setState(() {
            _webImageBytes = bytes;
          });
        } else {
          setState(() {
            _imageFile = File(photo.path);
          });
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo captured successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error taking picture: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error capturing photo: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
                      // Filter Button
                      Container(
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
                          child: PopupMenuButton<BugFilter>(
                            padding: EdgeInsets.zero,
                            icon: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.filter_list,
                                size: 24,
                                color: Colors.purple[400],
                              ),
                            ),
                            initialValue: _currentBugFilter,
                            onSelected: (BugFilter filter) {
                              _handleUserFilterChange(filter);
                            },
                            itemBuilder: (BuildContext context) => [
                              PopupMenuItem(
                                value: BugFilter.all,
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
                                value: BugFilter.createdByMe,
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
                                value: BugFilter.assignedToMe,
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
                            ],
                          ),
                        ),
                      ),
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
    // Ensure data is loaded
    if (_users.isEmpty || _projects.isEmpty) {
      await _loadData();
    }
    
    final _formKey = GlobalKey<FormState>();
    String? _description;
    String? _selectedProjectId;
    String? _selectedRecipientId;
    List<String> _selectedCCRecipients = [];
    String _selectedSeverity = 'low';
    File? _selectedFile;
    String? _tabUrl;
    bool _isSubmitting = false;

    // Create a StatefulBuilder to manage dialog state
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
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
                    // Header
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
                          onPressed: () => Navigator.pop(context),
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
                      items: ['low', 'medium', 'high'].map((severity) {
                        return DropdownMenuItem(
                          value: severity,
                          child: Text(
                            severity.toUpperCase(),
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
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.camera_alt,
                                          size: 48,
                                          color: Colors.purple[400],
                                        ),
                                        onPressed: _takePicture,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Take Photo',
                                        style: GoogleFonts.poppins(
                                          color: Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  height: 80,
                                  width: 1,
                                  color: Colors.grey[300],
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.photo_library,
                                          size: 48,
                                          color: Colors.purple[400],
                                        ),
                                        onPressed: () async {
                                          try {
                                            FilePickerResult? result = await FilePicker.platform.pickFiles(
                                              type: FileType.image,
                                              allowMultiple: false,
                                            );

                                            if (result != null) {
                                              setState(() {
                                                if (kIsWeb) {
                                                  _webImageBytes = result.files.first.bytes;
                                                } else {
                                                  _selectedFile = File(result.files.single.path!);
                                                }
                                              });
                                            }
                                          } catch (e) {
                                            print('Error picking file: $e');
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Error selecting image: $e')),
                                            );
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Choose from Gallery',
                                        style: GoogleFonts.poppins(
                                          color: Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_selectedFile != null || _webImageBytes != null)
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green[400],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Image selected',
                                      style: GoogleFonts.poppins(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      setState(() {
                                        _selectedFile = null;
                                        _webImageBytes = null;
                                      });
                                    },
                                    color: Colors.grey[600],
                                    iconSize: 20,
                                  ),
                                ],
                              ),
                            ),
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
                                  setState(() => _isSubmitting = true);
                                  try {
                                    await _bugReportService.uploadBugReport(
                                      description: _description!,
                                      recipientId: _selectedRecipientId!,
                                      ccRecipients: [],
                                      imageFile: _selectedFile,
                                      imageBytes: _webImageBytes,
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
    );
  }

  void _resetForm() {
    setState(() {
      _description = null;
      _selectedRecipient = null;
      _imageFile = null;
      _webImageBytes = null;
      _selectedSeverity = 'low';
      _selectedProject = null;
      _tabUrl = null;
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