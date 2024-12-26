import 'package:flutter/material.dart';
import '../models/bug_report.dart';
import '../models/bug_filter.dart';
import '../models/user.dart';
import '../services/bug_report_service.dart';
import '../services/logging_service.dart';

class BugReportProvider with ChangeNotifier {
  final BugReportService _bugReportService = BugReportService();
  final LoggingService _logger = LoggingService();
  
  List<BugReport> _bugReports = [];
  User? _currentUser;
  bool _isLoading = false;
  BugFilter _filter = BugFilter();
  String _error = '';

  // Getters
  List<BugReport> get bugReports => _bugReports;
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  BugFilter get filter => _filter;
  String get error => _error;

  // Initialize data
  Future<void> initialize() async {
    await getCurrentUser();
    if (_currentUser != null) {
      await loadBugReports();
    }
  }

  // Get current user
  Future<void> getCurrentUser() async {
    _setLoading(true);
    try {
      _logger.info('Getting current user');
      _currentUser = await _bugReportService.getCurrentUser();
      _logger.info('Current user loaded: ${_currentUser?.email}');
    } catch (e, stackTrace) {
      _error = 'Failed to get current user';
      _logger.error(_error, error: e, stackTrace: stackTrace);
    } finally {
      _setLoading(false);
    }
  }

  // Load bug reports based on filter
  Future<void> loadBugReports() async {
    if (_currentUser == null) {
      _error = 'No user logged in';
      return;
    }

    _setLoading(true);
    try {
      _logger.info('Loading bug reports for filter: ${_filter.toString()}');
      
      if (_filter.createdByMe) {
        _bugReports = await _bugReportService.getCreatedBugReports(_currentUser!.id);
      } else if (_filter.assignedToMe) {
        _bugReports = await _bugReportService.getAssignedBugReports(_currentUser!.id);
      }
      
      _error = '';
      _logger.info('Loaded ${_bugReports.length} bug reports');
    } catch (e, stackTrace) {
      _error = 'Failed to load bug reports';
      _logger.error(_error, error: e, stackTrace: stackTrace);
    } finally {
      _setLoading(false);
    }
  }

  // Toggle bug status
  Future<void> toggleBugStatus(int bugId) async {
    _setLoading(true);
    try {
      _logger.info('Toggling status for bug #$bugId');
      await _bugReportService.toggleBugStatus(bugId);
      await loadBugReports();
      _logger.info('Successfully toggled status for bug #$bugId');
    } catch (e, stackTrace) {
      _error = 'Failed to toggle bug status';
      _logger.error(_error, error: e, stackTrace: stackTrace);
    } finally {
      _setLoading(false);
    }
  }

  // Delete bug report
  Future<void> deleteBugReport(int bugId) async {
    _setLoading(true);
    try {
      _logger.info('Deleting bug #$bugId');
      await _bugReportService.deleteBugReport(bugId);
      await loadBugReports();
      _logger.info('Successfully deleted bug #$bugId');
    } catch (e, stackTrace) {
      _error = 'Failed to delete bug report';
      _logger.error(_error, error: e, stackTrace: stackTrace);
    } finally {
      _setLoading(false);
    }
  }

  // Update filter
  void updateFilter(BugFilter newFilter) {
    _logger.info('Updating filter: ${newFilter.toString()}');
    _filter = newFilter;
    loadBugReports(); // Reload bugs with new filter
    notifyListeners();
  }

  // Helper method to set loading state
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
} 