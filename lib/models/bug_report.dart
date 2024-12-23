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

extension SeverityLevelExtension on SeverityLevel {
  String get displayName {
    switch (this) {
      case SeverityLevel.high:
        return 'High';
      case SeverityLevel.medium:
        return 'Medium';
      case SeverityLevel.low:
        return 'Low';
    }
  }

  String get apiValue {
    return this.toString().split('.').last;
  }
}

class BugReport {
  final int id;
  final String description;
  final String imageUrl;
  final String? creator;
  final int? creatorId;
  final String? recipient;
  final int? recipientId;
  final List<String> ccRecipients;
  final SeverityLevel severity;
  final DateTime modifiedDate;
  final BugStatus status;
  final String mediaType;
  final int? projectId;
  final String? projectName;
  final String? tabUrl;

  BugReport({
    required this.id,
    required this.description,
    required this.imageUrl,
    this.creator,
    this.creatorId,
    this.recipient,
    this.recipientId,
    required this.ccRecipients,
    required this.severity,
    required this.modifiedDate,
    required this.status,
    required this.mediaType,
    this.projectId,
    this.projectName,
    this.tabUrl,
  });

  factory BugReport.fromJson(Map<String, dynamic> json) {
    try {
      return BugReport(
        id: json['id'] as int,
        description: json['description'] as String,
        imageUrl: json['image_url'] as String,
        creator: json['creator']?.toString(),
        creatorId: json['creator_id'] as int?,
        recipient: json['recipient']?.toString(),
        recipientId: json['recipient_id'] as int?,
        ccRecipients: (json['cc_recipients'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ?? [],
        severity: _parseSeverity(json['severity'] as String),
        modifiedDate: DateTime.parse(json['modified_date'] as String),
        status: _parseStatus(json['status'] as String),
        mediaType: json['media_type'] as String,
        projectId: json['project_id'] as int?,
        projectName: json['project_name']?.toString(),
        tabUrl: json['tab_url']?.toString(),
      );
    } catch (e) {
      print('Error parsing JSON to BugReport: $json');
      print('Error details: $e');
      rethrow;
    }
  }

  static BugStatus _parseStatus(String status) {
    try {
      return BugStatus.values.firstWhere(
        (e) => e.toString().split('.').last.toLowerCase() == status.toLowerCase(),
        orElse: () => BugStatus.assigned,
      );
    } catch (e) {
      print('Error parsing status: $status');
      return BugStatus.assigned;
    }
  }

  static SeverityLevel _parseSeverity(String severity) {
    try {
      return SeverityLevel.values.firstWhere(
        (e) => e.toString().split('.').last.toLowerCase() == severity.toLowerCase(),
        orElse: () => SeverityLevel.low,
      );
    } catch (e) {
      print('Error parsing severity: $severity');
      return SeverityLevel.low;
    }
  }

  Color get severityColor {
    switch (severity) {
      case SeverityLevel.high:
        return Colors.red;
      case SeverityLevel.medium:
        return Colors.orange;
      case SeverityLevel.low:
        return Colors.green;
      default:
        return Colors.grey;
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
} 