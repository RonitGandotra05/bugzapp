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
  final String description;
  final String creator;
  final String recipient;
  final int? creator_id;
  final int? recipient_id;
  final String? projectName;
  final DateTime modifiedDate;
  final BugStatus status;
  final SeverityLevel severity;
  final String? imageUrl;
  final String? mediaType;
  final String? tabUrl;

  BugReport({
    required this.id,
    required this.description,
    required this.creator,
    required this.recipient,
    this.creator_id,
    this.recipient_id,
    this.projectName,
    required this.modifiedDate,
    required this.status,
    required this.severity,
    this.imageUrl,
    this.mediaType,
    this.tabUrl,
  });

  factory BugReport.fromJson(Map<String, dynamic> json) {
    return BugReport(
      id: json['id'] as int,
      description: json['description'] as String,
      creator: json['creator'] as String? ?? 'Unknown',
      recipient: json['recipient'] as String? ?? 'Unassigned',
      creator_id: json['creator_id'] as int?,
      recipient_id: json['recipient_id'] as int?,
      projectName: json['project_name'] as String?,
      modifiedDate: DateTime.parse(json['modified_date'] as String),
      status: _parseStatus(json['status'] as String),
      severity: _parseSeverity(json['severity'] as String),
      imageUrl: json['image_url'] as String?,
      mediaType: json['media_type'] as String?,
      tabUrl: json['tab_url'] as String?,
    );
  }

  static BugStatus _parseStatus(String status) {
    return BugStatus.values.firstWhere(
      (e) => e.toString().split('.').last.toLowerCase() == status.toLowerCase(),
      orElse: () => BugStatus.assigned,
    );
  }

  static SeverityLevel _parseSeverity(String severity) {
    return SeverityLevel.values.firstWhere(
      (e) => e.toString().split('.').last.toLowerCase() == severity.toLowerCase(),
      orElse: () => SeverityLevel.low,
    );
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