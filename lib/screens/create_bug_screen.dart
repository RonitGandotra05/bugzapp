class _CreateBugScreenState extends State<CreateBugScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  String? _selectedRecipientId;
  List<String> _selectedCCRecipients = [];
  String _selectedSeverity = 'low';
  String? _selectedProjectId;
  File? _imageFile;
  bool _isLoading = false;
  List<User> _availableUsers = [];
  List<Project> _projects = [];
  final BugReportService _bugReportService = BugReportService();

  // ... other methods ...

  Future<void> _submitBugReport() async {
    if (!_formKey.currentState!.validate() || _isLoading) return;

    setState(() => _isLoading = true);
    try {
      await _bugReportService.createBugReport(
        description: _descriptionController.text.trim(),
        recipientId: _selectedRecipientId!,
        ccRecipients: _selectedCCRecipients,
        imageFile: _imageFile,
        severity: _selectedSeverity,
        projectId: _selectedProjectId,
        tabUrl: _tabUrlController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bug report created successfully')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating bug report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final users = await _bugReportService.fetchUsers();
      final projects = await _bugReportService.fetchProjects();
      
      if (mounted) {
        setState(() {
          _availableUsers = users;
          _projects = projects;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Widget _buildProjectDropdown() {
    return DropdownButtonFormField<String>(
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
    );
  }

  Widget _buildRecipientDropdown() {
    return DropdownButtonFormField<String>(
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
      items: _availableUsers.map((user) {
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Create Bug Report',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: Colors.purple[400],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildProjectDropdown(),
                  const SizedBox(height: 16),
                  _buildRecipientDropdown(),
                  const SizedBox(height: 16),
                  // Description TextField
                  TextFormField(
                    controller: _descriptionController,
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
                    validator: (value) => value?.isEmpty ?? true ? 'Description is required' : null,
                  ),
                  const SizedBox(height: 16),
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
                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitBugReport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple[400],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            )
                          : Text(
                              'Submit Bug Report',
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
    );
  }
} 