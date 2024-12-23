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
import '../widgets/stats_panel.dart';
import 'dart:convert';
import 'dart:math' show pi;

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

  void _handleFilterChange(BugFilterType filter) {
    setState(() {
      _currentFilter = filter;
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
        backgroundColor: Colors.transparent,
        elevation: 0,
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
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeInOut,
                  switchOutCurve: Curves.easeInOut,
                  child: ListView.builder(
                    key: ValueKey<BugFilterType>(_currentFilter),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 8),
                    itemCount: _filteredBugReports.length,
                    itemBuilder: (context, index) {
                      final bug = _filteredBugReports[index];
                      return BugCard(
                        bug: bug,
                        onStatusToggle: () => _toggleBugStatus(bug.id),
                        onSendReminder: () => _sendReminder(bug.id),
                      );
                    },
                  ),
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
      builder: (context) => AlertDialog(
        title: Text('Add Bug Report'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value?.isEmpty ?? true ? 'Description is required' : null,
                  onSaved: (value) => _description = value,
                ),
                SizedBox(height: 16),
                
                // Project Dropdown
                DropdownButtonFormField<Project>(
                  decoration: InputDecoration(
                    labelText: 'Project',
                    border: OutlineInputBorder(),
                  ),
                  items: _availableProjects.map((project) {
                    return DropdownMenuItem(
                      value: project,
                      child: Text(project.name),
                    );
                  }).toList(),
                  onChanged: (value) => _selectedProject = value,
                ),
                SizedBox(height: 16),

                // Recipient Dropdown
                DropdownButtonFormField<User>(
                  decoration: InputDecoration(
                    labelText: 'Recipient',
                    border: OutlineInputBorder(),
                  ),
                  items: _availableUsers.map((user) {
                    return DropdownMenuItem(
                      value: user,
                      child: Text(user.name),
                    );
                  }).toList(),
                  onChanged: (value) => _selectedRecipient = value,
                ),
                SizedBox(height: 16),

                // Severity Dropdown
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    labelText: 'Severity',
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedSeverity,
                  items: ['low', 'medium', 'high'].map((severity) {
                    return DropdownMenuItem(
                      value: severity,
                      child: Text(severity.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) => _selectedSeverity = value ?? 'low',
                ),
                SizedBox(height: 16),

                // File Upload Button
                ElevatedButton.icon(
                  icon: Icon(Icons.attach_file),
                  label: Text(_selectedFile?.path.split('/').last ?? 'Select Screenshot'),
                  onPressed: () async {
                    FilePickerResult? result = await FilePicker.platform.pickFiles(
                      type: FileType.image,
                    );
                    if (result != null) {
                      _selectedFile = File(result.files.single.path!);
                    }
                  },
                ),
                SizedBox(height: 16),

                // Tab URL TextField
                TextFormField(
                  decoration: InputDecoration(
                    labelText: 'Tab URL (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  onSaved: (value) => _tabUrl = value,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_formKey.currentState?.validate() ?? false) {
                _formKey.currentState?.save();
                try {
                  await _bugReportService.uploadBugReport(
                    description: _description!,
                    imageFile: _selectedFile,
                    recipientId: _selectedRecipient?.id.toString(),
                    ccRecipients: _selectedCCRecipients
                        .map((user) => user.id.toString())
                        .toList(),
                    severity: _selectedSeverity,
                    projectId: _selectedProject?.id.toString(),
                    tabUrl: _tabUrl,
                  );
                  
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Bug report created successfully')),
                    );
                    _loadData(); // Refresh the list
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error creating bug report: $e')),
                  );
                }
              }
            },
            child: Text('Submit'),
          ),
        ],
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }
} 