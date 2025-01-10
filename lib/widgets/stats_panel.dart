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
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatCard(
                'Total Bug\nReports',
                totalBugs.toString(),
                Icons.bug_report,
                Colors.blue[100]!,
                Colors.blue,
                () => onFilterChange(BugFilterType.all),
                isSelected: currentFilter == BugFilterType.all,
              ),
              _buildStatCard(
                'Resolved\nBugs',
                resolvedBugs.toString(),
                Icons.check_circle_outline,
                Colors.green[100]!,
                Colors.green,
                () => onFilterChange(BugFilterType.resolved),
                isSelected: currentFilter == BugFilterType.resolved,
              ),
              _buildStatCard(
                'Pending\nBugs',
                pendingBugs.toString(),
                Icons.pending_actions,
                Colors.orange[100]!,
                Colors.orange,
                () => onFilterChange(BugFilterType.pending),
                isSelected: currentFilter == BugFilterType.pending,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color bgColor,
    MaterialColor? accentColor,
    VoidCallback onTap,
    {bool isSelected = false}
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? accentColor?.withOpacity(0.1) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? accentColor ?? Colors.grey : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: accentColor,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
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