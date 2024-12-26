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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Create Bug Report',
          style: GoogleFonts.poppins(),
        ),
        backgroundColor: Colors.purple[400],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ... other form fields ...

            const SizedBox(height: 20),
            
            // Submit Button with loading state
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
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Creating Bug Report...',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
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