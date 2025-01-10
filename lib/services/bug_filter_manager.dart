class BugFilterManager {
  final List<BugReport> allBugs;
  final BugFilter userFilter;
  final BugFilterType statusFilter;
  final User? currentUser;
  final BugReportService bugReportService;
  final Set<int> selectedProjectIds;
  final String? searchQuery;

  BugFilterManager({
    required this.allBugs,
    required this.userFilter,
    required this.statusFilter,
    required this.currentUser,
    required this.bugReportService,
    required this.selectedProjectIds,
    this.searchQuery,
  });

  List<BugReport> get searchFiltered {
    List<BugReport> filtered = List.from(allBugs);
    
    // Apply project filter first
    if (selectedProjectIds.isNotEmpty) {
      filtered = filtered.where((bug) => 
        bug.projectId != null && selectedProjectIds.contains(bug.projectId)
      ).toList();
    }
    
    // Apply user filter
    switch (userFilter) {
      case BugFilter.assignedToMe:
        filtered = filtered.where((bug) => 
          bug.recipientId == currentUser?.id
        ).toList();
        break;
      case BugFilter.createdByMe:
        filtered = filtered.where((bug) => 
          bug.creatorId == currentUser?.id
        ).toList();
        break;
      case BugFilter.all:
      default:
        // No additional filtering needed
        break;
    }
    
    // Apply status filter
    switch (statusFilter) {
      case BugFilterType.resolved:
        filtered = filtered.where((bug) => 
          bug.status == BugStatus.resolved
        ).toList();
        break;
      case BugFilterType.pending:
        filtered = filtered.where((bug) => 
          bug.status == BugStatus.assigned
        ).toList();
        break;
      case BugFilterType.all:
      default:
        // No additional filtering needed
        break;
    }
    
    // Apply search query if present
    if (searchQuery != null && searchQuery!.isNotEmpty) {
      final query = searchQuery!.toLowerCase();
      filtered = filtered.where((bug) =>
        bug.description.toLowerCase().contains(query) ||
        bug.recipientName.toLowerCase().contains(query) ||
        bug.creatorName.toLowerCase().contains(query) ||
        (bug.projectName?.toLowerCase().contains(query) ?? false)
      ).toList();
    }
    
    return filtered;
  }

  int get totalBugs => searchFiltered.length;
  
  int get resolvedBugs => searchFiltered
    .where((bug) => bug.status == BugStatus.resolved)
    .length;
    
  int get pendingBugs => searchFiltered
    .where((bug) => bug.status == BugStatus.assigned)
    .length;
} 