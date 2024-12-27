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
    return BugReport(
      id: json['id'] as int,
      imageUrl: json['image_url'] as String?,
      description: json['description'] as String,
      recipientId: json['recipient_id'] as int?,
      creatorId: json['creator_id'] as int?,
      status: _parseStatus(json['status'] as String),
      recipient: json['recipient'] as String?,
      creator: json['creator'] as String?,
      mediaType: json['media_type'] as String?,
      modifiedDate: DateTime.parse(json['modified_date']),
      severity: _parseSeverity(json['severity'] as String),
      projectId: json['project_id'] as int?,
      projectName: json['project_name'] as String?,
      tabUrl: json['tab_url'] as String?,
      ccRecipients: (json['cc_recipients'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
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