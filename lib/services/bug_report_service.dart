import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_constants.dart';
import '../models/bug_report.dart';
import '../models/comment.dart';
import '../utils/token_storage.dart';
import 'dart:io';
import '../models/user.dart';
import '../models/project.dart';

class BugReportService {
  // Add enum for severity levels
  static const Map<String, String> severityDisplayMap = {
    'high': 'High',
    'medium': 'Medium', 
    'low': 'Low'
  };

  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await TokenStorage.getToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<List<BugReport>> getAllBugReports() async {
    try {
      final token = await TokenStorage.getToken();
      print('Using token: $token'); // Debug token

      final url = '${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}';
      print('Fetching from URL: $url'); // Debug URL

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      print('Response status code: ${response.statusCode}'); // Debug status
      print('Response headers: ${response.headers}'); // Debug headers
      print('Raw response body: ${response.body}'); // Debug body

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body) as List<dynamic>;
        print('Parsed data: $data');

        return data.map((item) {
          print('Processing item: $item'); // Debug each item
          if (item is! Map<String, dynamic>) {
            print('Invalid item format: $item');
            throw Exception('Invalid data format from server');
          }
          try {
            return BugReport.fromJson(item);
          } catch (e) {
            print('Error parsing bug report: $e');
            print('Problematic JSON: $item');
            rethrow;
          }
        }).toList();
      } else {
        throw Exception('Failed to load bug reports: ${response.body}');
      }
    } catch (e) {
      print('Error in getAllBugReports: $e');
      throw Exception('Error getting bug reports: $e');
    }
  }

  Future<List<BugReport>> getUserBugReports(int userId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/users/$userId/received_bug_reports'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => BugReport.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load user bug reports: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> toggleBugStatus(int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/toggle_status'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to toggle bug status: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> sendReminder(int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.bugReportsEndpoint}/$bugId/send_reminder'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to send reminder: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> createBugReport(
    String description,
    String recipientId,
    List<String> ccRecipients,
    File? imageFile,
    String severity,
    String? projectId,
    String? tabUrl
  ) async {
    try {
      final token = await TokenStorage.getToken();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'description': description,
          'recipient_id': recipientId,
          'cc_recipients': ccRecipients,
          'image_file': imageFile,
          'severity': severity,
          'project_id': projectId,
          'tab_url': tabUrl,
        }),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to create bug report: ${response.body}');
      }
    } catch (e) {
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<List<Project>> fetchProjects() async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.projectsEndpoint}'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Project.fromJson(json as Map<String, dynamic>)).toList();
      } else {
        throw Exception('Failed to load projects: ${response.body}');
      }
    } catch (e) {
      print('Error fetching projects: $e');
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<List<User>> fetchUsers() async {
    try {
      final headers = await _getAuthHeaders();
      print('Fetching users with headers: $headers');

      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.usersEndpoint}'),
        headers: headers,
      );

      print('Users response status: ${response.statusCode}');
      print('Users raw response: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> names = json.decode(response.body);
        
        // Convert string names to User objects with generated IDs
        return names.map((name) => User(
          id: names.indexOf(name), // Using index as temporary ID
          name: name.toString(),
          email: '', // Empty since not provided by API
          isAdmin: false, // Default value
        )).toList();
        
      } else {
        print('Failed to load users: ${response.body}');
        throw Exception('Failed to load users: ${response.body}');
      }
    } catch (e) {
      print('Error fetching users: $e');
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<BugReport> uploadBugReport({
    required String description,
    File? imageFile,
    String? recipientId,
    List<String> ccRecipients = const [],
    String severity = 'low', // Default to low if not specified
    String? projectId,
    String? tabUrl,
  }) async {
    try {
      // Validate severity
      if (!['high', 'medium', 'low'].contains(severity.toLowerCase())) {
        throw Exception('Invalid severity level. Must be high, medium, or low');
      }

      // Validate CC recipients
      if (ccRecipients.length > 4) {
        throw Exception('Maximum 4 CC recipients allowed');
      }

      final token = await TokenStorage.getToken();
      var uri = Uri.parse('${ApiConstants.baseUrl}/upload');
      var request = http.MultipartRequest('POST', uri);

      // Add headers
      request.headers.addAll({
        'Authorization': 'Bearer $token',
      });

      // Add required fields
      request.fields['description'] = description;

      // Add optional fields only if they have values
      if (recipientId != null) {
        request.fields['recipient_id'] = recipientId;
      }
      
      if (ccRecipients.isNotEmpty) {
        request.fields['cc_recipients'] = jsonEncode(ccRecipients);
      }
      
      request.fields['severity'] = severity.toLowerCase();
      
      if (projectId != null) {
        request.fields['project_id'] = projectId;
      }
      
      if (tabUrl != null) {
        request.fields['tab_url'] = tabUrl;
      }

      // Add file if present
      if (imageFile != null) {
        // Check file size (16MB limit)
        if (await imageFile.length() > 16 * 1024 * 1024) {
          throw Exception('File size exceeds 16MB limit');
        }

        var stream = http.ByteStream(imageFile.openRead());
        var length = await imageFile.length();
        var multipartFile = http.MultipartFile(
          'file',
          stream,
          length,
          filename: imageFile.path.split('/').last
        );
        request.files.add(multipartFile);
      }

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      if (response.statusCode != 201) {
        throw Exception('Failed to upload bug report: $responseBody');
      }

      // Parse the response
      final Map<String, dynamic> responseData = json.decode(responseBody);
      
      // Create a BugReport object from the response
      return BugReport.fromJson({
        'id': responseData['id'],
        'description': responseData['description'],
        'creator': '', // Will be filled by backend
        'creator_id': 0, // Will be filled by backend
        'recipient': responseData['recipient'] ?? '',
        'recipient_id': 0, // Will be filled by backend if recipient exists
        'cc_recipients': responseData['cc_recipients'] ?? [],
        'severity': responseData['severity'] ?? 'low',
        'created_date': DateTime.now().toIso8601String(), // Will be overwritten by backend
        'modified_date': DateTime.now().toIso8601String(), // Will be overwritten by backend
        'status': 'assigned', // Default status for new bug reports
        'project_name': responseData['project_name'],
        'image_url': responseData['url'],
        'media_type': responseData['media_type'],
        'tab_url': responseData['tab_url'],
      });

    } catch (e) {
      throw Exception('Failed to upload bug report: $e');
    }
  }

  Future<List<Comment>> getBugComments(int bugId) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/$bugId/comments'),
        headers: headers,
      );

      print('Comments response: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Comment.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load comments: ${response.body}');
      }
    } catch (e) {
      print('Error getting comments: $e');
      throw Exception('Failed to connect to server: $e');
    }
  }

  Future<void> addComment(int bugId, String comment) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('${ApiConstants.baseUrl}/bug_reports/$bugId/comments'),
        headers: {
          ...headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'comment': comment,
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to add comment: ${response.body}');
      }
    } catch (e) {
      print('Error adding comment: $e');
      throw Exception('Failed to connect to server: $e');
    }
  }
} 