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
  final int commentCount;

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
    this.commentCount = 0,
  });

  factory BugReport.fromJson(Map<String, dynamic> json) {
    // Parse the modified_date string to DateTime in UTC
    DateTime? modifiedDate;
    if (json['modified_date'] != null) {
      // Parse UTC time without converting to IST
      modifiedDate = DateTime.parse(json['modified_date']);
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

    // Parse CC recipients
    final ccRecipients = (json['cc_recipients'] as List<dynamic>?)?.map((recipient) {
      if (recipient is Map<String, dynamic>) {
        return recipient['name'] as String;
      }
      return recipient as String;
    }).toList() ?? [];

    return BugReport(
      id: json['id'] as int,
      description: json['description'] as String,
      imageUrl: json['image_url'] as String?,
      status: _parseStatus(json['status'] as String),
      severity: _parseSeverity(json['severity'] as String),
      creator: creator,
      recipient: recipient,
      mediaType: json['media_type'] as String?,
      modifiedDate: modifiedDate ?? DateTime.now(),  // Store as UTC
      projectName: projectName,
      tabUrl: json['tab_url'] as String?,
      ccRecipients: ccRecipients,
      creatorId: creatorData?['id'] ?? json['creator_id'],
      recipientId: recipientData?['id'] ?? json['recipient_id'],
      projectId: projectData?['id'] ?? json['project_id'],
      commentCount: json['comment_count'] as int? ?? 0,
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

  String get creatorName => creator ?? 'Unknown';
  
  bool get isRead => false; // Default to false until we implement read status tracking

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

  bool get hasComments => commentCount > 0;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'description': description,
      'image_url': imageUrl,
      'status': status.toString().split('.').last,
      'severity': severity.toString().split('.').last,
      'creator': creator,
      'recipient': recipient,
      'media_type': mediaType,
      'modified_date': modifiedDate.toUtc().toIso8601String(),
      'project_name': projectName,
      'tab_url': tabUrl,
      'cc_recipients': ccRecipients,
      'creator_id': creatorId,
      'recipient_id': recipientId,
      'project_id': projectId,
      'comment_count': commentCount,
    };
  }
} 