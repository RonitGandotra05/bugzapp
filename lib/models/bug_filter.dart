import 'bug_report.dart';

enum BugSortOption {
  newest,
  oldest,
  severity,
  status
}

class BugFilter {
  final String? project;
  final String? creator;
  final String? assignee;
  final BugStatus? status;
  final SeverityLevel? severity;
  final BugSortOption sortBy;
  final bool ascending;

  BugFilter({
    this.project,
    this.creator,
    this.assignee,
    this.status,
    this.severity,
    this.sortBy = BugSortOption.newest,
    this.ascending = false,
  });

  BugFilter copyWith({
    String? project,
    String? creator,
    String? assignee,
    BugStatus? status,
    SeverityLevel? severity,
    BugSortOption? sortBy,
    bool? ascending,
  }) {
    return BugFilter(
      project: project ?? this.project,
      creator: creator ?? this.creator,
      assignee: assignee ?? this.assignee,
      status: status ?? this.status,
      severity: severity ?? this.severity,
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
    );
  }
} 