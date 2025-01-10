import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bug_filter.dart';

class StatsPanel extends StatelessWidget {
  final String userName;
  final int totalBugs;
  final int resolvedBugs;
  final int pendingBugs;
  final Function(BugFilterType) onFilterChange;
  final BugFilterType currentFilter;

  const StatsPanel({
    Key? key,
    required this.userName,
    required this.totalBugs,
    required this.resolvedBugs,
    required this.pendingBugs,
    required this.onFilterChange,
    required this.currentFilter,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.purple[300]!,
            Colors.purple[400]!,
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Total Bugs
          Expanded(
            child: _buildStatCard(
              icon: Icons.bug_report,
              count: totalBugs,
              label: 'Total Bug\nReports',
              isSelected: currentFilter == BugFilterType.all,
              onTap: () => onFilterChange(BugFilterType.all),
            ),
          ),
          const SizedBox(width: 8),
          // Resolved Bugs
          Expanded(
            child: _buildStatCard(
              icon: Icons.check_circle_outline,
              count: resolvedBugs,
              label: 'Resolved\nBugs',
              isSelected: currentFilter == BugFilterType.resolved,
              onTap: () => onFilterChange(BugFilterType.resolved),
              iconColor: Colors.green,
            ),
          ),
          const SizedBox(width: 8),
          // Pending Bugs
          Expanded(
            child: _buildStatCard(
              icon: Icons.pending_actions,
              count: pendingBugs,
              label: 'Pending\nBugs',
              isSelected: currentFilter == BugFilterType.pending,
              onTap: () => onFilterChange(BugFilterType.pending),
              iconColor: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required int count,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Material(
      color: isSelected ? Colors.purple[400] : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : (iconColor ?? Colors.purple[400]),
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                count.toString(),
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: isSelected ? Colors.white : Colors.grey[600],
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 