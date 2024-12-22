import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bug_report.dart';
import '../services/bug_report_service.dart';
import '../utils/token_storage.dart';
import '../widgets/bug_card.dart';
import 'login_screen.dart';
import '../models/bug_filter.dart';
import '../widgets/bug_filter_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import '../models/user.dart';
import '../models/project.dart';
import '../constants/api_constants.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _bugReportService = BugReportService();
  bool _isLoading = true;
  bool _isAdmin = false;
  int? _userId;
  List<BugReport> _bugReports = [];
  String _selectedFilter = 'all'; // 'all', 'assigned', 'resolved'
  BugFilter _filter = BugFilter();
  List<String> _projects = [];
  List<String> _creators = [];
  List<String> _assignees = [];

  // Add these properties for background effects
  Offset _mousePosition = Offset.zero;
  bool _isCardHovered = false;

  // Add these getters to calculate the counts
  int get _totalBugs => _bugReports.length;

  int get _assignedBugs => _bugReports.where((b) => b.status == BugStatus.assigned).length;

  int get _resolvedBugs => _bugReports.where((b) => b.status == BugStatus.resolved).length;

  // Add these properties to your state class
  List<String> _availableUsers = [];
  Uint8List? _selectedImageBytes;
  String? _selectedFileName;

  // Add these to your existing state variables
  final _descriptionController = TextEditingController();
  Map<String, dynamic>? _selectedProject;
  String? _selectedRecipient;
  String _selectedSeverity = 'low';

  // Add this to your state class
  List<String> _errors = [];

  // Add to state class
  List<String> _selectedCCRecipients = [];

  // Add to state class
  List<Map<String, dynamic>> _availableProjects = [];
  int? _selectedProjectId;

  // Add these variables
  bool _isUploading = false;

  final Dio _dio = Dio();

  // Define the _tabUrl variable
  String? _tabUrl;

  @override
  void initState() {
    super.initState();
    _loadUserDataAndBugs();
  }

  Future<void> _loadUserDataAndBugs() async {
    setState(() => _isLoading = true);
    try {
      _isAdmin = await TokenStorage.getIsAdmin();
      _userId = await TokenStorage.getUserId();
      await _loadBugReports();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadBugReports() async {
    try {
      final reports = await _bugReportService.getAllBugReports();
      
      // Filter bugs based on user role and ID
      List<BugReport> filteredReports = [];
      if (_isAdmin) {
        // Admin can see all bugs
        filteredReports = reports;
      } else {
        // Regular users can only see bugs they created or are assigned to
        filteredReports = reports.where((bug) {
          return bug.creatorId == _userId || // Created by the user
                  bug.recipientId == _userId || // Assigned to the user
                  bug.ccRecipients.contains(_userId); // User is in CC
        }).toList();
      }
      
      // Sort the bug reports based on filter
      filteredReports.sort((a, b) {
        switch (_filter.sortBy) {
          case BugSortOption.newest:
            return b.modifiedDate.compareTo(a.modifiedDate);
          case BugSortOption.oldest:
            return a.modifiedDate.compareTo(b.modifiedDate);
          case BugSortOption.severity:
            // Sort by severity (high to low)
            final severityOrder = {
              SeverityLevel.high: 3,
              SeverityLevel.medium: 2,
              SeverityLevel.low: 1,
            };
            final result = severityOrder[b.severity]!.compareTo(severityOrder[a.severity]!);
            return _filter.ascending ? -result : result;
          case BugSortOption.status:
            // Sort by status (assigned first, then resolved)
            final statusOrder = {
              BugStatus.assigned: 2,
              BugStatus.resolved: 1,
            };
            final result = statusOrder[b.status]!.compareTo(statusOrder[a.status]!);
            return _filter.ascending ? -result : result;
        }
      });

      // If ascending is true, reverse the list (except for severity and status which handle it above)
      if (_filter.ascending && 
          _filter.sortBy != BugSortOption.severity && 
          _filter.sortBy != BugSortOption.status) {
        filteredReports.reversed.toList();
      }

      // Update the lists for filtering
      final Set<String> projects = {};
      final Set<String> creators = {};
      final Set<String> assignees = {};

      for (var report in filteredReports) {
        if (report.projectName != null) projects.add(report.projectName!);
        if (report.creator.isNotEmpty) creators.add(report.creator);
        if (report.recipient.isNotEmpty) assignees.add(report.recipient);
      }

      if (mounted) {
        setState(() {
          _bugReports = filteredReports;
          _projects = projects.toList()..sort();
          _creators = creators.toList()..sort();
          _assignees = assignees.toList()..sort();
        });
      }
    } catch (e) {
      _logError('Error loading bug reports: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading bug reports: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _loadFilterOptions() {
    _projects = _bugReports
        .where((bug) => bug.projectName != null)
        .map((bug) => bug.projectName!)
        .toSet()
        .toList();
    
    _creators = _bugReports
        .map((bug) => bug.creator)
        .toSet()
        .toList();
    
    _assignees = _bugReports
        .map((bug) => bug.recipient)
        .toSet()
        .toList();
  }

  List<BugReport> get _filteredBugReports {
    return _bugReports.where((bug) {
      // First apply the chip filter
      if (_selectedFilter == 'assigned' && bug.status != BugStatus.assigned) {
        return false;
      }
      if (_selectedFilter == 'resolved' && bug.status != BugStatus.resolved) {
        return false;
      }

      // Then apply the advanced filters
      if (_filter.project != null && bug.projectName != _filter.project) {
        return false;
      }
      if (_filter.creator != null && bug.creator != _filter.creator) {
        return false;
      }
      if (_filter.assignee != null && bug.recipient != _filter.assignee) {
        return false;
      }
      if (_filter.severity != null && bug.severity != _filter.severity) {
        return false;
      }

      return true;
    }).toList()
      ..sort((a, b) {
        int comparison;
        switch (_filter.sortBy) {
          case BugSortOption.newest:
            comparison = b.modifiedDate.compareTo(a.modifiedDate);
            break;
          case BugSortOption.oldest:
            comparison = a.modifiedDate.compareTo(b.modifiedDate);
            break;
          case BugSortOption.severity:
            final severityOrder = {
              SeverityLevel.high: 3,
              SeverityLevel.medium: 2,
              SeverityLevel.low: 1,
            };
            comparison = severityOrder[b.severity]!.compareTo(severityOrder[a.severity]!);
            break;
          case BugSortOption.status:
            comparison = a.status.index.compareTo(b.status.index);
            break;
        }
        return _filter.ascending ? -comparison : comparison;
      });
  }

  Future<void> _logout() async {
    await TokenStorage.deleteToken();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  Future<void> _refreshBugs() async {
    await _loadBugReports();
    setState(() {});
  }

  Future<void> _showCreateBugDialog() async {
    // Reset state before showing dialog
    _selectedImageBytes = null;
    _selectedFileName = null;
    _selectedProject = null;
    _selectedRecipient = null;
    _selectedSeverity = 'low';
    _descriptionController.clear();

    await _loadDialogData();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false,
          child: StatefulBuilder(
            builder: (context, setDialogState) => Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 600,  // Increased from default
                  maxHeight: 800, // Added to prevent overflow on smaller screens
                ),
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Image Selection
                      ElevatedButton.icon(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.image),
                        label: const Text('Select Image'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildImagePreview(),
                      const SizedBox(height: 16),

                      Text(
                        'Create Bug Report',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              StatefulBuilder(
                                builder: (context, setDialogState) {
                                  return AlertDialog(
                                    content: Column(
                                      children: [
                                        TextField(
                                          controller: _descriptionController,
                                          decoration: const InputDecoration(
                                            labelText: 'Description',
                                            hintText: 'Enter bug description',
                                          ),
                                          maxLines: 3,
                                        ),
                                        const SizedBox(height: 16),

                                        DropdownButtonFormField<Map<String, dynamic>>(
                                          decoration: const InputDecoration(labelText: 'Project'),
                                          value: _selectedProject,
                                          items: _availableProjects.map((project) {
                                            return DropdownMenuItem(
                                              value: project,
                                              child: Text(
                                                project['name'],
                                                style: GoogleFonts.poppins(),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (value) {
                                            setDialogState(() {
                                              _selectedProject = value;
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 16),

                                        DropdownButtonFormField<String>(
                                          decoration: const InputDecoration(labelText: 'Assign To'),
                                          value: _selectedRecipient,
                                          items: _availableUsers.map((user) {
                                            return DropdownMenuItem(
                                              value: user,
                                              child: Text(user),
                                            );
                                          }).toList(),
                                          onChanged: (value) {
                                            setDialogState(() {
                                              _selectedRecipient = value;
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 16),

                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'CC Recipients (max 4)',
                                              style: GoogleFonts.poppins(
                                                color: Colors.grey[600],
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            ..._selectedCCRecipients.asMap().entries.map((entry) {
                                              int index = entry.key;
                                              String recipient = entry.value;
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 8),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      child: DropdownButtonFormField<String>(
                                                        decoration: InputDecoration(
                                                          labelText: 'CC Recipient ${index + 1}',
                                                          isDense: true,
                                                        ),
                                                        value: recipient,
                                                        items: _availableUsers
                                                            .where((user) => user != _selectedRecipient && 
                                                                !_selectedCCRecipients
                                                                    .where((cc) => cc != recipient)
                                                                    .contains(user))
                                                            .map((user) {
                                                          return DropdownMenuItem(
                                                            value: user,
                                                            child: Text(user),
                                                          );
                                                        }).toList(),
                                                        onChanged: (value) {
                                                          if (value != null) {
                                                            setDialogState(() {
                                                              _selectedCCRecipients[index] = value;
                                                            });
                                                          }
                                                        },
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.remove_circle_outline),
                                                      color: Colors.red[400],
                                                      onPressed: () {
                                                        setDialogState(() {
                                                          _selectedCCRecipients.removeAt(index);
                                                        });
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                            if (_selectedCCRecipients.length < 4)
                                              TextButton.icon(
                                                onPressed: () {
                                                  if (_selectedCCRecipients.length < 4) {
                                                    setDialogState(() {
                                                      _selectedCCRecipients.add(_availableUsers.first);
                                                    });
                                                  }
                                                },
                                                icon: const Icon(Icons.add),
                                                label: const Text('Add CC Recipient'),
                                              ),
                                          ],
                                        ),

                                        DropdownButtonFormField<String>(
                                          decoration: const InputDecoration(labelText: 'Priority'),
                                          value: _selectedSeverity,
                                          items: ['low', 'medium', 'high'].map((priority) {  // Changed to lowercase
                                            return DropdownMenuItem(
                                              value: priority,
                                              child: Text(
                                                priority[0].toUpperCase() + priority.substring(1),  // Capitalize first letter for display
                                                style: GoogleFonts.poppins(),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (value) {
                                            setDialogState(() {
                                              _selectedSeverity = value!;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: Text(
                                      'Cancel',
                                      style: GoogleFonts.poppins(),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  ElevatedButton(
                                    onPressed: () {
                                      if (_selectedImageBytes == null) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Please select an image')),
                                        );
                                        return;
                                      }
                                      if (_selectedProjectId == null) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Please select a project')),
                                        );
                                        return;
                                      }
                                      if (_selectedRecipient == null) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Please select a recipient')),
                                        );
                                        return;
                                      }
                                      Navigator.pop(context, true);
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFA855F7),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                    ),
                                    child: Text(
                                      'Create',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
      },
    );

    if (result == true) {
      try {
        final formData = {
          'file': await MultipartFile.fromBytes(
            _selectedImageBytes!,
            filename: _selectedFileName ?? 'screenshot.png',
          ),
          'description': _descriptionController.text,
          'project_id': _selectedProjectId!.toString(),
          'recipient_name': _selectedRecipient ?? '',
          'severity': _selectedSeverity,
          if (_selectedCCRecipients.isNotEmpty)
            'cc_recipients': _selectedCCRecipients.join(','),
        };

        await _bugReportService.uploadBugReport(formData);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bug report created successfully'),
              backgroundColor: Colors.green,
            ),
          );
          await _refreshBugs();
        }
      } catch (e) {
        _logError('Error creating bug report: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating bug report: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _loadDialogData() async {
    try {
      final projects = await _bugReportService.fetchProjects();
      final users = await _bugReportService.fetchUsers();
      setState(() {
        _availableProjects = projects;
        _availableUsers = users;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        child: Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.purple.shade300,
                      Colors.purple.shade500,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(
                      Icons.bug_report,
                      color: Colors.white,
                      size: 50,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'BugzApp',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: Text(
                  'Logout',
                  style: GoogleFonts.poppins(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () async {
                  // Show confirmation dialog
                  final shouldLogout = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(
                        'Confirm Logout',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      content: Text(
                        'Are you sure you want to logout?',
                        style: GoogleFonts.poppins(),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.poppins(),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(
                            'Logout',
                            style: GoogleFonts.poppins(
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                  
                  if (shouldLogout == true) {
                    await TokenStorage.deleteToken();
                    if (mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const LoginScreen(),
                        ),
                        (route) => false,
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        // Add leading menu icon that opens drawer
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          'Bug Reports',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
          ),
        ),
        // ... rest of your AppBar configuration
      ),
      body: Stack(
        children: [
          MouseRegion(
            onHover: (event) {
              if (!_isCardHovered) {
                setState(() {
                  _mousePosition = event.localPosition;
                });
              }
            },
            child: Stack(
              children: [
                // Animated Background
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: const [
                        Color(0xFFE9D5FF),  // Light purple/white blend
                        Color(0xFFD8B4FE),  // Lighter purple
                        Color(0xFFC084FC),  // Medium purple
                        Color(0xFFA855F7),  // Darker purple
                      ],
                      stops: const [0.0, 0.3, 0.6, 1.0],
                    ),
                  ),
                  child: CustomPaint(
                    painter: ShimmerPainter(_mousePosition),
                    size: Size.infinite,
                  ),
                ),

                // Main Content
                SafeArea(
                  child: Column(
                    children: [
                      // AppBar replacement
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(24),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.menu),
                              onPressed: () {
                                // Add drawer functionality if needed
                              },
                            ),
                            AppBar(
                              centerTitle: true,
                              title: const Text(
                                '虫',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.filter_list),
                                  onPressed: () async {
                                    final result = await showDialog<BugFilter>(
                                      context: context,
                                      builder: (context) => BugFilterDialog(
                                        currentFilter: _filter,
                                        projects: _projects,
                                        creators: _creators,
                                        assignees: _assignees,
                                      ),
                                    );
                                    if (result != null) {
                                      setState(() {
                                        _filter = result;
                                      });
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.logout),
                                  onPressed: _logout,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Scrollable content
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : RefreshIndicator(
                                onRefresh: _refreshBugs,
                                child: ListView(
                                  padding: const EdgeInsets.all(16),
                                  children: [
                                    // Stats Cards
                                    Row(
                                      children: [
                                        _buildStatCard(
                                          'Total',
                                          _totalBugs.toString(),
                                          Icons.bug_report,
                                          const Color(0xFF7C3AED),
                                        ),
                                        const SizedBox(width: 16),
                                        _buildStatCard(
                                          'Assigned',
                                          _assignedBugs.toString(),
                                          Icons.assignment,
                                          const Color(0xFFDC2626),
                                        ),
                                        const SizedBox(width: 16),
                                        _buildStatCard(
                                          'Resolved',
                                          _resolvedBugs.toString(),
                                          Icons.check_circle,
                                          const Color(0xFF059669),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Filter Chips and Sort Button
                                    Row(
                                      children: [
                                        Expanded(
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: [
                                                _buildFilterChip('All', 'all'),
                                                const SizedBox(width: 8),
                                                _buildFilterChip('Assigned', 'assigned'),
                                                const SizedBox(width: 8),
                                                _buildFilterChip('Resolved', 'resolved'),
                                              ],
                                            ),
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.sort),
                                          tooltip: 'Sort bugs',
                                          onSelected: (value) {
                                            setState(() {
                                              switch (value) {
                                                case 'newest':
                                                  _filter = _filter.copyWith(
                                                    sortBy: BugSortOption.newest,
                                                    ascending: false,
                                                  );
                                                  break;
                                                case 'oldest':
                                                  _filter = _filter.copyWith(
                                                    sortBy: BugSortOption.oldest,
                                                    ascending: true,
                                                  );
                                                  break;
                                              }
                                            });
                                          },
                                          itemBuilder: (context) => [
                                            const PopupMenuItem(
                                              value: 'newest',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.arrow_upward),
                                                  SizedBox(width: 8),
                                                  Text('Newest First'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'oldest',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.arrow_downward),
                                                  SizedBox(width: 8),
                                                  Text('Oldest First'),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Bug List
                                    ..._filteredBugReports.map((bug) => Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: Center(
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 400),
                                          child: BugCard(
                                            bug: bug,
                                            onStatusToggle: () async {
                                              try {
                                                await _bugReportService.toggleBugStatus(bug.id);
                                                await _refreshBugs();
                                              } catch (e) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('Error: $e')),
                                                  );
                                                }
                                              }
                                            },
                                            onSendReminder: () async {
                                              try {
                                                await _bugReportService.sendReminder(bug.id);
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('Reminder sent successfully'),
                                                      backgroundColor: Colors.green,
                                                    ),
                                                  );
                                                }
                                              } catch (e) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('Error: $e')),
                                                  );
                                                }
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    )).toList(),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Add the error display as an overlay
          if (_errors.isNotEmpty)
            Positioned(
              bottom: 80,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Errors',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: Icon(Icons.clear),
                          onPressed: () => setState(() => _errors.clear()),
                        ),
                      ],
                    ),
                    ..._errors.map((e) => Text(e)).toList(),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: Colors.white,  // Simple white background
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),  // Very subtle shadow
              offset: Offset(0, 1),
              blurRadius: 2,
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _showCreateBugDialog,
          backgroundColor: Colors.transparent,
          hoverColor: Colors.transparent,  // Remove hover color
          focusColor: Colors.transparent,  // Remove focus color
          splashColor: Colors.transparent, // Remove splash color
          highlightElevation: 0,          // Remove highlight elevation
          hoverElevation: 0,              // Remove hover elevation
          elevation: 0,                   // Remove default elevation
          icon: Icon(
            Icons.add,
            color: Colors.grey[800],
          ),
          label: Text(
            'Report Bug',
            style: GoogleFonts.poppins(
              color: Colors.grey[800],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color baseColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              baseColor.withOpacity(1),      // Full color at top-left
              baseColor.withOpacity(0.8),    // Slightly darker
              baseColor.withOpacity(0.9),    // Light reflection
              baseColor.withOpacity(0.7),    // Darker edge
            ],
            stops: const [0.0, 0.3, 0.6, 1.0],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            // Outer shadow
            BoxShadow(
              color: baseColor.withOpacity(0.5),
              blurRadius: 12,
              spreadRadius: -2,
              offset: const Offset(4, 4),
            ),
            // Inner highlight
            BoxShadow(
              color: Colors.white.withOpacity(0.25),
              blurRadius: 12,
              spreadRadius: -2,
              offset: const Offset(-4, -4),
            ),
          ],
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.05),
              ],
            ),
          ),
          child: Column(
            children: [
              // Shine effect at the top
              Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.5),
                      Colors.white.withOpacity(0.1),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Icon(
                icon,
                color: Colors.white,
                size: 28,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.3),
                    offset: const Offset(2, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.3),
                      offset: const Offset(2, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: Colors.white.withOpacity(0.95),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.2),
                      offset: const Offset(1, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      selected: isSelected,
      label: Text(
        label,
        style: GoogleFonts.poppins(
          color: isSelected ? Colors.white : Colors.grey[800],
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selectedColor: Colors.blue[700],
      backgroundColor: Colors.white.withOpacity(0.7),
      checkmarkColor: Colors.white,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  // Add this method to log errors
  void _logError(String error) {
    setState(() {
      _errors.add(error);
    });
  }

  // Add this method
  void _clearForm() {
    setState(() {
      _selectedImageBytes = null;
      _selectedFileName = null;
      _selectedProject = null;
      _selectedRecipient = null;
      _selectedSeverity = 'low';
      _descriptionController.clear();
      _selectedCCRecipients.clear();
    });
  }

  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        lockParentWindow: true,
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() {
            _selectedImageBytes = file.bytes;
            _selectedFileName = file.name;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Image selected successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          throw Exception('Failed to read image data');
        }
      }
    } catch (e) {
      _logError('Error picking image: $e');
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

  Future<void> _handleSubmit() async {
    if (_selectedImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an image'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedFileName == null || _selectedFileName!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid image file'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          _selectedImageBytes!,
          filename: _selectedFileName ?? 'screenshot.png',
        ),
        'description': _descriptionController.text,
        if (_selectedRecipient != null)
          'recipient_name': _selectedRecipient,
        if (_selectedCCRecipients.isNotEmpty)
          'cc_recipients': _selectedCCRecipients.join(','),
        'severity': _selectedSeverity,
        if (_selectedProject != null && _selectedProject!['id'] != null)
          'project_id': _selectedProject!['id'].toString(),
        if (_tabUrl != null && _tabUrl!.isNotEmpty)
          'tab_url': _tabUrl,
      });

      setState(() => _isLoading = true);

      final response = await _dio.post(
        '${ApiConstants.baseUrl}/upload',
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${await TokenStorage.getToken()}',
          },
        ),
      );

      if (response.statusCode == 200) {
        setState(() {
          _selectedImageBytes = null;
          _selectedFileName = null;
          _descriptionController.clear();
          _selectedRecipient = null;
          _selectedCCRecipients.clear();
          _selectedSeverity = 'low';
          _selectedProject = null;
          _tabUrl = '';
        });

        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bug report created successfully')),
        );
        _loadBugReports();
      }
    } catch (e) {
      _logError('Error creating bug report: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating bug report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildImagePreview() {
    if (_selectedImageBytes != null) {
      return Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Image.memory(
          _selectedImageBytes!,
          fit: BoxFit.contain,
        ),
      );
    }
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Text('No image selected'),
      ),
    );
  }

  Future<void> _showFilterDialog() async {
    final result = await showDialog<BugFilter>(
      context: context,
      builder: (context) => BugFilterDialog(
        currentFilter: _filter,
        projects: _projects,
        creators: _creators,
        assignees: _assignees,
      ),
    );

    if (result != null) {
      setState(() {
        _filter = result;
        // Trigger reload with new filter
        _loadBugReports();
      });
    }
  }
} 