import 'package:flutter/material.dart';

enum BugStatus {
  assigned,
  resolved
}

enum SeverityLevel {
  high,
  medium,
  low
}

class BugReport {
  final int id;
  final String? imageUrl;
  final String description;
  final int? recipientId;
  final int? creatorId;
  final BugStatus status;
  final String? recipient;
  final String? creator;
  final String? mediaType;
  final DateTime modifiedDate;
  final SeverityLevel severity;
  final int? projectId;
  final String? projectName;
  final String? tabUrl;
  final List<String> ccRecipients;

  BugReport({
    required this.id,
    this.imageUrl,
    required this.description,
    this.recipientId,
    this.creatorId,
    required this.status,
    this.recipient,
    this.creator,
    this.mediaType,
    required this.modifiedDate,
    required this.severity,
    this.projectId,
    this.projectName,
    this.tabUrl,
    this.ccRecipients = const [],
  });

  factory BugReport.fromJson(Map<String, dynamic> json) {
    // Parse the modified_date string to DateTime in IST
    DateTime? modifiedDate;
    if (json['modified_date'] != null) {
      // Parse UTC time and convert to IST by adding 5 hours and 30 minutes
      modifiedDate = DateTime.parse(json['modified_date']).add(Duration(hours: 5, minutes: 30));
    }

    // Handle creator data
    Map<String, dynamic>? creatorData = json['creator'] is Map ? json['creator'] as Map<String, dynamic> : null;
    String? creator = creatorData?['name'] ?? json['creator']?.toString();

    // Handle recipient data
    Map<String, dynamic>? recipientData = json['recipient'] is Map ? json['recipient'] as Map<String, dynamic> : null;
    String? recipient = recipientData?['name'] ?? json['recipient']?.toString();

    // Handle project data
    Map<String, dynamic>? projectData = json['project'] is Map ? json['project'] as Map<String, dynamic> : null;
    String? projectName = projectData?['name'] ?? json['project_name']?.toString();

    return BugReport(
      id: json['id'] as int,
      description: json['description'] as String,
      imageUrl: json['image_url'] as String?,
      status: _parseStatus(json['status'] as String),
      severity: _parseSeverity(json['severity'] as String),
      creator: creator,
      recipient: recipient,
      mediaType: json['media_type'] as String?,
      modifiedDate: modifiedDate ?? DateTime.now().add(Duration(hours: 5, minutes: 30)),
      projectName: projectName,
      tabUrl: json['tab_url'] as String?,
      ccRecipients: (json['cc_recipients'] as List<dynamic>?)?.cast<String>() ?? [],
      creatorId: creatorData?['id'] ?? json['creator_id'],
      recipientId: recipientData?['id'] ?? json['recipient_id'],
      projectId: projectData?['id'] ?? json['project_id'],
    );
  }

  static BugStatus _parseStatus(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return BugStatus.assigned;
      case 'resolved':
        return BugStatus.resolved;
      default:
        return BugStatus.assigned;
    }
  }

  static SeverityLevel _parseSeverity(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return SeverityLevel.high;
      case 'medium':
        return SeverityLevel.medium;
      case 'low':
        return SeverityLevel.low;
      default:
        return SeverityLevel.low;
    }
  }

  String get severityText {
    return severity.toString().split('.').last[0].toUpperCase() +
           severity.toString().split('.').last.substring(1).toLowerCase();
  }

  String get statusText {
    return status.toString().split('.').last[0].toUpperCase() +
           status.toString().split('.').last.substring(1).toLowerCase();
  }

  Color get severityColor {
    switch (severity) {
      case SeverityLevel.high:
        return Colors.red;
      case SeverityLevel.medium:
        return Colors.orange;
      case SeverityLevel.low:
        return Colors.green;
    }
  }
} 