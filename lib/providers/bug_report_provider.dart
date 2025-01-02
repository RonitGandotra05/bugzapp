import 'package:flutter/material.dart';
import 'dart:async';
import '../models/bug_report.dart';
import '../models/bug_filter.dart';
import '../models/user.dart';
import '../models/comment.dart';
import '../services/bug_report_service.dart';
import '../services/logging_service.dart';

class BugReportProvider with ChangeNotifier {
  final BugReportService _bugReportService;
  List<BugReport> _bugReports = [];
  User? _currentUser;
  bool _isLoading = false;
  bool _isInitializing = false;
  String _error = '';
  Timer? _refreshTimer;
  Timer? _debounceTimer;
  bool _mounted = true;
  
  BugReportProvider(this._bugReportService) {
    initialize();
  }

  List<BugReport> get bugReports => _bugReports;
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String get error => _error;

  @override
  void dispose() {
    _mounted = false;
    _refreshTimer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> initialize() async {
    if (_isInitializing || !_mounted) return;
    _isInitializing = true;
    _error = '';
    
    try {
      _isLoading = true;
      notifyListeners();

      // Get current user with timeout
      _currentUser = await _getCurrentUserWithTimeout();
      if (!_mounted) return;
      
      if (_currentUser == null) {
        _error = 'Failed to get current user';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Load all comments first
      await _bugReportService.loadAllComments();

      // Load bug reports
      await loadBugReports();
      
      // Start periodic refresh if not already running
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
        if (_mounted) loadBugReports(silent: true);
      });
    } catch (e) {
      _error = 'Error initializing: $e';
    } finally {
      _isInitializing = false;
      if (_mounted) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<User?> _getCurrentUserWithTimeout() async {
    try {
      return await _bugReportService.getCurrentUser().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Getting current user timed out'),
      );
    } catch (e) {
      _error = 'Error getting current user: $e';
      return null;
    }
  }

  Future<void> loadBugReports({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      // Load all bug reports
      final reports = await _bugReportService.getAllBugReports().timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('Loading bug reports timed out'),
      );
      
      if (!_mounted) return;
      
      _bugReports = reports;
      _error = '';
      
      // Cache comments in background
      _cacheCommentsInBackground();
    } catch (e) {
      _error = 'Error loading bug reports: $e';
    } finally {
      if (!silent && _mounted) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void _cacheCommentsInBackground() {
    for (final bug in _bugReports) {
      _bugReportService.getComments(bug.id).then((_) {
        // Comments are now cached
      }).catchError((e) {
        print('Error caching comments for bug #${bug.id}: $e');
      });
    }
  }

  Future<void> toggleBugStatus(int bugId) async {
    try {
      await _bugReportService.toggleBugStatus(bugId);
      await loadBugReports();
    } catch (e) {
      _error = 'Error toggling bug status: $e';
      notifyListeners();
    }
  }

  Future<void> deleteBugReport(int bugId) async {
    try {
      await _bugReportService.deleteBugReport(bugId);
      _bugReports.removeWhere((bug) => bug.id == bugId);
      notifyListeners();
    } catch (e) {
      _error = 'Error deleting bug report: $e';
      notifyListeners();
    }
  }

  Future<void> sendReminder(int bugId) async {
    try {
      await _bugReportService.sendReminder(bugId);
    } catch (e) {
      _error = 'Error sending reminder: $e';
      notifyListeners();
    }
  }

  void reset() {
    _bugReports = [];
    _currentUser = null;
    _isLoading = false;
    _error = '';
    _refreshTimer?.cancel();
    _debounceTimer?.cancel();
    notifyListeners();
  }
} 