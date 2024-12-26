import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  bool _isLoading = true;
  Project? _selectedProject;
  List<BugReport> _projectBugReports = [];
  String _sortBy = 'date';
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _loadProjectsImmediately();
  }

  // Fast initial load of projects
  Future<void> _loadProjectsImmediately() async {
    try {
      // First try to get cached projects for immediate display
      final cachedProjects = await _bugReportService.fetchProjects(useCache: true);
      if (mounted && cachedProjects.isNotEmpty) {
        setState(() {
          _projects = cachedProjects;
          _isLoading = false;
        });
      }

      // Then refresh from server in background
      _loadProjects();
    } catch (e) {
      // If cache fails, load from server
      _loadProjects();
    }
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await _bugReportService.fetchProjects(useCache: false);
      if (!mounted) return;
      
      setState(() {
        _projects = projects;
        _isLoading = false;
      });

      // Pre-fetch bug reports for each project in background
      for (final project in projects) {
        _bugReportService.getBugReportsInProject(project.id).then((bugReports) {
          // Bug reports are now cached
          // Pre-fetch comments for each bug report
          for (final bug in bugReports) {
            _bugReportService.getComments(bug.id).catchError((e) {
              // Silently handle error as this is background loading
              print('Error pre-fetching comments for bug #${bug.id}: $e');
            });
          }
        }).catchError((e) {
          // Silently handle error as this is background loading
          print('Error pre-fetching bug reports for project #${project.id}: $e');
        });
      }
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading projects: $e')),
      );
    }
  }

  Future<void> _loadProjectBugReports(int projectId) async {
    try {
      // First try to get cached bug reports for immediate display
      final cachedReports = await _bugReportService.getBugReportsInProject(projectId, useCache: true);
      if (mounted && cachedReports.isNotEmpty) {
        setState(() {
          _projectBugReports = _sortBugReports(cachedReports);
        });
      }

      // Then load fresh data from server
      final bugReports = await _bugReportService.getBugReportsInProject(projectId, useCache: false);
      if (!mounted) return;
      
      setState(() {
        _projectBugReports = _sortBugReports(bugReports);
      });

      // Pre-fetch comments for each bug report in the background
      for (final bug in bugReports) {
        _bugReportService.getComments(bug.id).then((comments) {
          // Comments are now cached
        }).catchError((e) {
          // Silently handle error as this is background loading
          print('Error pre-fetching comments for bug #${bug.id}: $e');
        });
      }
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading bug reports: $e')),
      );
    }
  }

  List<BugReport> _sortBugReports(List<BugReport> reports) {
    switch (_sortBy) {
      case 'date':
        reports.sort((a, b) => _sortAscending
            ? a.modifiedDate.compareTo(b.modifiedDate)
            : b.modifiedDate.compareTo(a.modifiedDate));
        break;
      case 'severity':
        reports.sort((a, b) {
          final severityOrder = {'high': 0, 'medium': 1, 'low': 2};
          final aValue = severityOrder[a.severityText.toLowerCase()] ?? 3;
          final bValue = severityOrder[b.severityText.toLowerCase()] ?? 3;
          return _sortAscending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
        });
        break;
      case 'status':
        reports.sort((a, b) {
          final statusOrder = {'assigned': 0, 'resolved': 1};
          final aValue = statusOrder[a.statusText.toLowerCase()] ?? 2;
          final bValue = statusOrder[b.statusText.toLowerCase()] ?? 2;
          return _sortAscending ? aValue.compareTo(bValue) : bValue.compareTo(aValue);
        });
        break;
    }
    return reports;
  }

  void _handleSort(String? value) {
    if (value != null) {
      setState(() {
        if (_sortBy == value) {
          _sortAscending = !_sortAscending;
        } else {
          _sortBy = value;
          _sortAscending = false;
        }
        _projectBugReports = _sortBugReports(_projectBugReports);
      });
    }
  }

  Future<void> _showCreateProjectDialog() async {
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

  Future<void> _showDeleteProjectDialog(Project project) async {
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
                  SnackBar(
                    content: Text('Error deleting project: $e'),
                    backgroundColor: Colors.red,
                  ),
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
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBugDetails(BugReport bug) {
    // Show the dialog immediately
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => BugDetailsDialog(
        bug: bug,
        imageUrl: bug.imageUrl,
        mediaType: bug.mediaType,
        tabUrl: bug.tabUrl,
        bugReportService: _bugReportService,
      ),
    );

    // Pre-fetch comments in the background
    _bugReportService.getComments(bug.id).then((comments) {
      // Comments are now cached for instant access
    }).catchError((e) {
      // Silently handle error as this is background loading
      print('Error pre-fetching comments for bug #${bug.id}: $e');
    });
  }

  Future<void> _handleRemoveFromProject(BugReport bug) async {
    try {
      await _bugReportService.removeBugReportFromProject(
        _selectedProject!.id,
        bug.id,
      );
      _loadProjectBugReports(_selectedProject!.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bug report removed from project'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error removing bug report: $e'),
        ),
      );
    }
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
              child: Row(
                children: [
                  // Projects List
                  Container(
                    width: 300,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Projects',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _projects.length,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemBuilder: (context, index) {
                              final project = _projects[index];
                              final isSelected = _selectedProject?.id == project.id;
                              return ListTile(
                                selected: isSelected,
                                selectedTileColor: Colors.purple[50],
                                leading: Icon(
                                  Icons.folder,
                                  color: isSelected ? Colors.purple[400] : Colors.grey[600],
                                ),
                                title: Text(
                                  project.name,
                                  style: GoogleFonts.poppins(
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  project.description ?? 'No description',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Colors.red[400],
                                  ),
                                  onPressed: () => _showDeleteProjectDialog(project),
                                  tooltip: 'Delete Project',
                                ),
                                onTap: () {
                                  setState(() {
                                    _selectedProject = project;
                                  });
                                  _loadProjectBugReports(project.id);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Bug Reports List
                  Expanded(
                    child: _selectedProject == null
                        ? Center(
                            child: Text(
                              'Select a project to view bug reports',
                              style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Bug Reports in ${_selectedProject!.name}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SortDropdown(
                                      value: _sortBy,
                                      ascending: _sortAscending,
                                      onChanged: _handleSort,
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _projectBugReports.length,
                                  padding: const EdgeInsets.all(16),
                                  itemBuilder: (context, index) {
                                    final bug = _projectBugReports[index];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: InkWell(
                                        onTap: () => _showBugDetails(bug),
                                        child: BugCard(
                                          bug: bug,
                                          onStatusToggle: () {
                                            _loadProjectBugReports(_selectedProject!.id);
                                          },
                                          onSendReminder: () async {
                                            try {
                                              final response = await _bugReportService.sendReminder(bug.id);
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
                                                          style: TextStyle(fontSize: 12),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Error sending reminder: $e'),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          },
                                          onDelete: () async {
                                            try {
                                              await _bugReportService.deleteBugReport(bug.id);
                                              _loadProjectBugReports(_selectedProject!.id);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Bug report deleted successfully')),
                                              );
                                            } catch (e) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Error deleting bug report: $e'),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateProjectDialog,
        child: const Icon(Icons.create_new_folder),
        backgroundColor: Colors.purple[400],
      ),
    );
  }
} 