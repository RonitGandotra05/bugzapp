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

  BugFilterManager({
    required this.allBugs,
    required this.userFilter,
    required this.statusFilter,
    required this.currentUser,
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
    return filteredByStatus.where((bug) =>
      bug.description.toLowerCase().contains(searchLower) ||
      (bug.creator?.toLowerCase() ?? '').contains(searchLower) ||
      (bug.recipient?.toLowerCase() ?? '').contains(searchLower) ||
      bug.severityText.toLowerCase().contains(searchLower) ||
      bug.statusText.toLowerCase().contains(searchLower) ||
      (bug.projectName?.toLowerCase() ?? '').contains(searchLower)
    ).toList();
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
    );
    _loadData();
  }

  void _updateFilterManager() {
    _filterManager = BugFilterManager(
      allBugs: _bugReports,
      userFilter: _currentBugFilter,
      statusFilter: _currentFilter,
      currentUser: _currentUser,
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
    });

    try {
      // Load current user first
      final currentUser = await _bugReportService.getCurrentUser();
      if (currentUser == null) {
        _handleLogout();
        return;
      }

      print('Current user loaded in HomeScreen:');
      print('  Name: ${currentUser.name}');
      print('  Email: ${currentUser.email}');
      print('  Is Admin: ${currentUser.isAdmin}');

      final users = await _bugReportService.fetchUsers();
      final projects = await _bugReportService.fetchProjects();
      final bugReports = await _bugReportService.getAllBugReports();

      if (mounted) {
        setState(() {
          _currentUser = currentUser;
          _userName = currentUser.name;
          _users = users;
          _projects = projects;
          _bugReports = bugReports;
          _availableUsers = users;
          _availableProjects = projects;
          _isLoading = false;
        });

        // Preload comments for visible bug reports
        final visibleBugIds = _getVisibleBugIds();
        await _bugReportService.preloadComments(visibleBugIds);
      }
    } catch (e) {
      print('Error loading data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
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

  Widget _buildStatsPanel() {
    return StatsPanel(
      userName: _userName.capitalize(),
      totalBugs: _getTotalBugs(),
      resolvedBugs: _getResolvedBugs(),
      pendingBugs: _getPendingBugs(),
      onFilterChange: _handleStatusFilterChange,
      currentFilter: _currentFilter,
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
      body: Container(
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
    await TokenStorage.deleteToken();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  Future<void> _showAddBugReport(BuildContext context) async {
    // Ensure data is loaded
    if (_availableUsers.isEmpty) {
      await _loadData();
    }
    
    final _formKey = GlobalKey<FormState>();
    String? _description;
    Project? _selectedProject;
    User? _selectedRecipient;
    List<User> _selectedCCRecipients = [];
    String _selectedSeverity = 'low';
    File? _selectedFile;
    String? _tabUrl;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
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

                  // Description Field
                  TextFormField(
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Description',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!),
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
                    validator: (value) =>
                        value?.isEmpty ?? true ? 'Description is required' : null,
                    onSaved: (value) => _description = value,
                  ),
                  const SizedBox(height: 20),

                  // Project Dropdown
                  DropdownButtonFormField<Project>(
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
                    items: _availableProjects.map((project) {
                      return DropdownMenuItem(
                        value: project,
                        child: Text(project.name),
                      );
                    }).toList(),
                    onChanged: (value) => _selectedProject = value,
                  ),
                  const SizedBox(height: 20),

                  // Recipient Dropdown
                  StatefulBuilder(
                    builder: (context, setStateDialog) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<User>(
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
                          hint: Text('Select Recipient'),
                          value: _selectedRecipient,
                          items: _availableUsers.map((User user) {
                            return DropdownMenuItem<User>(
                              value: user,
                              child: Text(
                                user.name,
                                style: GoogleFonts.poppins(fontSize: 14),
                              ),
                            );
                          }).toList(),
                          validator: (value) => value == null ? 'Please select a recipient' : null,
                          onChanged: (User? value) {
                            print('Selected User: ${value?.name} (ID: ${value?.id})');
                            setStateDialog(() {
                              _selectedRecipient = value;
                            });
                          },
                        ),
                        if (_availableUsers.isEmpty && !_isLoading)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              'No users available',
                              style: GoogleFonts.poppins(
                                color: Colors.red[400],
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // CC Recipients MultiSelect
                  StatefulBuilder(
                    builder: (context, setStateDialog) => Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey[50],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CC Recipients (Max 4)',
                            style: GoogleFonts.poppins(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              // Selected Recipients Chips
                              ..._selectedCCRecipients.map((user) => Chip(
                                label: Text(
                                  user.name,
                                  style: GoogleFonts.poppins(fontSize: 12),
                                ),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () {
                                  setStateDialog(() {
                                    _selectedCCRecipients.remove(user);
                                  });
                                },
                              )),
                              // Add Button (if limit not reached)
                              if (_selectedCCRecipients.length < 4)
                                ActionChip(
                                  label: Text(
                                    'Add',
                                    style: GoogleFonts.poppins(
                                      color: Colors.purple[400],
                                      fontSize: 12,
                                    ),
                                  ),
                                  avatar: Icon(
                                    Icons.add,
                                    size: 16,
                                    color: Colors.purple[400],
                                  ),
                                  backgroundColor: Colors.purple[50],
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(
                                          'Add CC Recipient',
                                          style: GoogleFonts.poppins(),
                                        ),
                                        content: DropdownButtonFormField<User>(
                                          decoration: InputDecoration(
                                            labelText: 'Select User',
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          items: _availableUsers
                                              .where((user) => !_selectedCCRecipients.contains(user))
                                              .map((user) => DropdownMenuItem(
                                                    value: user,
                                                    child: Text(user.name),
                                                  ))
                                              .toList(),
                                          onChanged: (user) {
                                            if (user != null) {
                                              setStateDialog(() {
                                                _selectedCCRecipients.add(user);
                                              });
                                              Navigator.pop(context);
                                            }
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
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
                    onChanged: (value) => _selectedSeverity = value ?? 'low',
                  ),
                  const SizedBox(height: 20),

                  // Tab URL TextField
                  TextFormField(
                    decoration: InputDecoration(
                      labelText: 'Tab URL (Optional)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!),
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
                    onSaved: (value) => _tabUrl = value,
                  ),
                  const SizedBox(height: 20),

                  // File Upload and Preview
                  StatefulBuilder(
                    builder: (context, setState) => Column(
                      children: [
                        Container(
                          width: double.infinity,
                          height: 100,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[50],
                          ),
                          child: InkWell(
                            onTap: () async {
                              try {
                                FilePickerResult? result = await FilePicker.platform.pickFiles(
                                  type: FileType.image,
                                  withData: true,  // This ensures we get the bytes on web
                                );
                                
                                if (result != null) {
                                  setState(() {
                                    if (kIsWeb) {
                                      _webImageBytes = result.files.first.bytes;
                                      _selectedFile = null;
                                    } else {
                                      _selectedFile = File(result.files.first.path!);
                                      _webImageBytes = null;
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
                            borderRadius: BorderRadius.circular(12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 32,
                                  color: Colors.purple[300],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _selectedFile != null 
                                      ? 'Image Selected'  // Generic text for both platforms
                                      : 'Select Screenshot',
                                  style: GoogleFonts.poppins(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_selectedFile != null || _webImageBytes != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            height: 200,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Image preview
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: kIsWeb 
                                      ? (_webImageBytes != null 
                                          ? Image.memory(
                                              _webImageBytes!,
                                              fit: BoxFit.cover,
                                            )
                                          : Container())
                                      : Image.file(
                                          _selectedFile!,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                                // Remove button
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    child: InkWell(
                                      onTap: () => setState(() {
                                        _selectedFile = null;
                                        _webImageBytes = null;
                                      }),
                                      borderRadius: BorderRadius.circular(20),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Icon(
                                          Icons.close,
                                          size: 20,
                                          color: Colors.red[400],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.poppins(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StatefulBuilder(
                          builder: (context, setSubmitState) => ElevatedButton(
                            onPressed: _isSubmitting ? null : () async {
                              if (_formKey.currentState?.validate() ?? false) {
                                _formKey.currentState?.save();
                                
                                if (_selectedRecipient == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please select a recipient')),
                                  );
                                  return;
                                }

                                setSubmitState(() {
                                  _isSubmitting = true;
                                });

                                try {
                                  print('Selected recipient: ${_selectedRecipient?.id}');
                                  
                                  await _bugReportService.uploadBugReport(
                                    description: _description!,
                                    recipientId: _selectedRecipient!.id.toString(),
                                    ccRecipients: _selectedCCRecipients.map((user) => user.name).toList(),
                                    imageFile: _selectedFile,
                                    imageBytes: _webImageBytes,
                                    severity: _selectedSeverity,
                                    projectId: _selectedProject?.id.toString(),
                                    tabUrl: _tabUrl,
                                  );
                                  
                                  if (mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Bug report created successfully')),
                                    );
                                    _loadData();
                                  }
                                } catch (e) {
                                  print('Error creating bug report: $e');
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error creating bug report: $e')),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setSubmitState(() {
                                      _isSubmitting = false;
                                    });
                                  }
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please fill in all required fields')),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple[400],
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Text(
                                    'Submit',
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
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
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1)}";
  }
} 