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
  final String? imageUrl;
  final String description;
  final int? creator_id;
  final int? recipient_id;
  final String? creator;
  final String? recipient;
  final BugStatus status;
  final String mediaType;
  final DateTime modifiedDate;
  final String severity;
  final int? projectId;
  final String? projectName;
  final String? tabUrl;
  final List<String> ccRecipients;

  BugReport({
    required this.id,
    this.imageUrl,
    required this.description,
    this.creator_id,
    this.recipient_id,
    this.creator,
    this.recipient,
    required this.status,
    required this.mediaType,
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
      creator_id: json['creator_id'] as int?,
      recipient_id: json['recipient_id'] as int?,
      creator: json['creator'] as String?,
      recipient: json['recipient'] as String?,
      status: _parseStatus(json['status'] as String),
      mediaType: json['media_type'] as String,
      modifiedDate: DateTime.parse(json['modified_date'] as String),
      severity: json['severity'] as String,
      projectId: json['project_id'] as int?,
      projectName: json['project_name'] as String?,
      tabUrl: json['tab_url'] as String?,
      ccRecipients: (json['cc_recipients'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
    );
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