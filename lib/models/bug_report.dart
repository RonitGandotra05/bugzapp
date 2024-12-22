import 'package:flutter/material.dart';

enum BugStatus {
  assigned,
  resolved
}

enum SeverityLevel {
  low,
  medium,
  high
}

class BugReport {
  final int id;
  final String description;
  final String creator;
  final int creatorId;
  final String recipient;
  final int recipientId;
  final List<int> ccRecipients;
  final SeverityLevel severity;
  final DateTime createdDate;
  final DateTime modifiedDate;
  final BugStatus status;
  final String? projectName;
  final String? imageUrl;
  final String? mediaType;
  final String? tabUrl;

  BugReport({
    required this.id,
    required this.description,
    required this.creator,
    required this.creatorId,
    required this.recipient,
    required this.recipientId,
    required this.ccRecipients,
    required this.severity,
    required this.createdDate,
    required this.modifiedDate,
    required this.status,
    this.projectName,
    this.imageUrl,
    this.mediaType,
    this.tabUrl,
  });

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

  factory BugReport.fromJson(Map<String, dynamic> json) {
    return BugReport(
      id: json['id'],
      description: json['description'],
      creator: json['creator'],
      creatorId: json['creator_id'],
      recipient: json['recipient'],
      recipientId: json['recipient_id'],
      ccRecipients: (json['cc_recipients'] as List<dynamic>?)
          ?.map((e) => e as int)
          ?.toList() ?? [],
      severity: _parseSeverity(json['severity']),
      createdDate: DateTime.parse(json['created_date']),
      modifiedDate: DateTime.parse(json['modified_date']),
      status: _parseStatus(json['status']),
      projectName: json['project_name'],
      imageUrl: json['image_url'] as String?,
      mediaType: json['media_type'] as String?,
      tabUrl: json['tab_url'],
    );
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