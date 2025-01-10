import 'bug_report.dart';

enum BugSortOption {
  newest,
  oldest,
  severity,
  status,
}

enum BugFilterType {
  all,
  resolved,
  pending,
}

class BugFilter {
  final String? project;
  final String? creator;
  final String? assignee;
  final BugStatus? status;
  final SeverityLevel? severity;
  final bool createdByMe;
  final bool assignedToMe;
  final BugSortOption sortBy;
  final bool ascending;
  final Set<int>? projectIds;

  BugFilter({
    this.project,
    this.creator,
    this.assignee,
    this.status,
    this.severity,
    this.createdByMe = false,
    this.assignedToMe = false,
    this.sortBy = BugSortOption.newest,
    this.ascending = false,
    this.projectIds,
  });

  @override
  String toString() {
    return 'BugFilter(project: $project, creator: $creator, assignee: $assignee, status: ${status?.name}, severity: ${severity?.name}, createdByMe: $createdByMe, assignedToMe: $assignedToMe, sortBy: $sortBy, ascending: $ascending, projectIds: $projectIds)';
  }

  BugFilter copyWith({
    String? project,
    String? creator,
    String? assignee,
    BugStatus? status,
    SeverityLevel? severity,
    bool? createdByMe,
    bool? assignedToMe,
    BugSortOption? sortBy,
    bool? ascending,
    Set<int>? projectIds,
  }) {
    return BugFilter(
      project: project ?? this.project,
      creator: creator ?? this.creator,
      assignee: assignee ?? this.assignee,
      status: status ?? this.status,
      severity: severity ?? this.severity,
      createdByMe: createdByMe ?? this.createdByMe,
      assignedToMe: assignedToMe ?? this.assignedToMe,
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
      projectIds: projectIds ?? this.projectIds,
    );
  }

  bool matchesProject(int? projectId) {
    if (projectIds == null || projectIds!.isEmpty) return true;
    return projectId != null && projectIds!.contains(projectId);
  }
} 