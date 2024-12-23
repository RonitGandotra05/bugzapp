import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../widgets/stats_panel.dart';
import 'dart:convert';
import 'dart:math' show pi;
import 'package:universal_html/html.dart' as html;

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

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final BugReportService _bugReportService = BugReportService();
  String _userName = '';
  bool _isLoading = false;
  List<BugReport> _bugReports = [];
  List<Project> _availableProjects = [];
  List<User> _availableUsers = [];
  BugFilterType _currentFilter = BugFilterType.all;
  File? _selectedFile;
  bool _isAscendingOrder = false;
  Uint8List? _webImageBytes;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadUserName();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final projects = await _bugReportService.fetchProjects();
      final users = await _bugReportService.fetchUsers();
      final reports = await _bugReportService.getAllBugReports();
      
      if (mounted) {
        setState(() {
          _availableProjects = projects;
          _availableUsers = users;
          _bugReports = reports;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadUserName() async {
    final token = await TokenStorage.getToken();
    if (token != null) {
      setState(() {
        final email = token.split('.')[1];
        final decoded = utf8.decode(base64Url.decode(base64Url.normalize(email)));
        final data = json.decode(decoded);
        _userName = data['sub'].toString().split('@')[0];  // Get username from email
      });
    }
  }

  List<BugReport> get _filteredBugReports {
    switch (_currentFilter) {
      case BugFilterType.resolved:
        return _bugReports.where((bug) => bug.status == BugStatus.resolved).toList();
      case BugFilterType.pending:
        return _bugReports.where((bug) => bug.status == BugStatus.assigned).toList();
      case BugFilterType.all:
      default:
        return _bugReports;
    }
  }

  List<BugReport> get _sortedAndFilteredBugReports {
    final filtered = _filteredBugReports;
    return List.from(filtered)..sort((a, b) => _isAscendingOrder 
      ? a.modifiedDate.compareTo(b.modifiedDate)
      : b.modifiedDate.compareTo(a.modifiedDate));
  }

  void _handleFilterChange(BugFilterType filter) {
    setState(() {
      _currentFilter = filter;
    });
  }

  void _toggleSortOrder() {
    setState(() {
      _isAscendingOrder = !_isAscendingOrder;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
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
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(
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
              child: ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.15),
                      Colors.white.withOpacity(0.05),
                      Colors.white.withOpacity(0.15),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                    transform: GradientRotation(pi / 4),
                  ).createShader(bounds);
                },
                blendMode: BlendMode.srcOver,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 30,
                      child: Icon(Icons.person, size: 36, color: Color(0xFF673AB7)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _userName.capitalize(),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
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
              onTap: () {
                Navigator.pop(context);
                _handleLogout();
              },
            ),
          ],
        ),
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
              child: StatsPanel(
                userName: _userName.capitalize(),
                totalBugs: _bugReports.length,
                resolvedBugs: _bugReports.where((bug) => bug.status == BugStatus.resolved).length,
                pendingBugs: _bugReports.where((bug) => bug.status == BugStatus.assigned).length,
                onFilterChange: _handleFilterChange,
                currentFilter: _currentFilter,
              ),
            ),
            // Bug List
            SliverToBoxAdapter(
              child: Container(
                color: const Color(0xFFFAF9F6),
                child: Column(
                  children: [
                    // Sort button
                    Padding(
                      padding: const EdgeInsets.only(right: 16.0, top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
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
                                    size: 20,
                                    color: Colors.purple[400],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Bug list
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeInOut,
                      switchOutCurve: Curves.easeInOut,
                      child: ListView.builder(
                        key: ValueKey<BugFilterType>(_currentFilter),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(top: 8),
                        itemCount: _sortedAndFilteredBugReports.length,
                        itemBuilder: (context, index) {
                          final bug = _sortedAndFilteredBugReports[index];
                          return BugCard(
                            bug: bug,
                            onStatusToggle: () => _toggleBugStatus(bug.id),
                            onSendReminder: () => _sendReminder(bug.id),
                          );
                        },
                      ),
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

  Future<void> _sendReminder(int bugId) async {
    try {
      await _bugReportService.sendReminder(bugId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reminder sent successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending reminder: $e')),
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
                    items: _availableUsers.map((user) {
                      return DropdownMenuItem(
                        value: user,
                        child: Text(user.name),
                      );
                    }).toList(),
                    onChanged: (value) => _selectedRecipient = value,
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
                        child: ElevatedButton(
                          onPressed: () async {
                            // ... existing submit logic ...
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple[400],
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Submit',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
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
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }
} 