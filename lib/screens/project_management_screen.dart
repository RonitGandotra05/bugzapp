import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/bug_report_service.dart';
import '../models/project.dart';
import '../models/bug_report.dart';
import '../widgets/bug_card.dart';
import '../widgets/sort_dropdown.dart';
import '../widgets/bug_details_dialog.dart';

class ProjectManagementScreen extends StatefulWidget {
  const ProjectManagementScreen({Key? key}) : super(key: key);

  @override
  _ProjectManagementScreenState createState() => _ProjectManagementScreenState();
}

class _ProjectManagementScreenState extends State<ProjectManagementScreen> {
  final BugReportService _bugReportService = BugReportService();
  List<Project> _projects = [];
  Project? _selectedProject;
  List<BugReport> _projectBugReports = [];
  bool _isLoading = true;
  String _sortBy = 'date';
  bool _sortAscending = false;
  final PageController _pageController = PageController();
  bool _isAdmin = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    try {
      final user = await _bugReportService.getCurrentUser();
      if (mounted) {
        setState(() {
          _isAdmin = user?.isAdmin ?? false;
        });
      }
    } catch (e) {
      print('Error checking admin status: $e');
    }
  }

  Future<void> _loadProjects() async {
    try {
      // First, try to get projects from cache
      final cachedProjects = await _bugReportService.fetchProjects(fromCache: true);
      if (mounted && cachedProjects.isNotEmpty) {
        setState(() {
          _projects = cachedProjects;
          _isLoading = false;
        });
      }

      // Then fetch fresh data in background
      final freshProjects = await _bugReportService.fetchProjects(fromCache: false);
      if (mounted && !listEquals(freshProjects, _projects)) {
        setState(() {
          _projects = freshProjects;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading projects: $e')),
        );
      }
    }
  }

  Future<void> _showAddProjectDialog() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create New Project',
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Project Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(Icons.folder),
                  ),
                  validator: (value) => value?.isEmpty ?? true ? 'Project name is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 3,
                  validator: (value) => value?.isEmpty ?? true ? 'Description is required' : null,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () async {
                        if (formKey.currentState?.validate() ?? false) {
                          try {
                            await _bugReportService.createProject(
                              name: nameController.text.trim(),
                              description: descriptionController.text.trim(),
                            );
                            Navigator.pop(context);
                            _loadProjects();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Project created successfully')),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error creating project: $e')),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple[400],
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Create',
                        style: GoogleFonts.poppins(
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
      ),
    );
  }

  Future<void> _showDeleteConfirmation(Project project) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Delete Project',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.red[700],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete ${project.name}?',
              style: GoogleFonts.poppins(),
            ),
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone. All bug reports will be unassigned from this project.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _bugReportService.deleteProject(project.id);
                Navigator.pop(context);
                _loadProjects();
                setState(() {
                  if (_selectedProject?.id == project.id) {
                    _selectedProject = null;
                    _projectBugReports = [];
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${project.name} has been deleted'),
                    backgroundColor: Colors.red[400],
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error deleting project: $e')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[400],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.poppins(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Project Management',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: Colors.purple[400],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProjects,
            tooltip: 'Refresh Projects',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.purple[50]!,
                    Colors.white,
                  ],
                ),
              ),
              child: ListView.builder(
                itemCount: _projects.length,
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final project = _projects[index];
                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(
                        project.name,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: project.description != null
                          ? Text(
                              project.description!,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            )
                          : null,
                      trailing: _isAdmin
                          ? IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: Colors.red[400],
                              ),
                              onPressed: () => _showDeleteConfirmation(project),
                              tooltip: 'Delete Project',
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton(
              onPressed: _showAddProjectDialog,
              child: const Icon(Icons.add),
              backgroundColor: Colors.purple[400],
            )
          : null,
    );
  }
} 