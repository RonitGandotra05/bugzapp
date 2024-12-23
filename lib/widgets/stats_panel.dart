import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class StatsPanel extends StatelessWidget {
  final String userName;
  final int totalBugs;
  final int resolvedBugs;
  final int pendingBugs;

  const StatsPanel({
    Key? key,
    required this.userName,
    required this.totalBugs,
    required this.resolvedBugs,
    required this.pendingBugs,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth - 48) / 3; // Divide screen width by 3 with padding

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome Back, $userName',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (pendingBugs > 0)
                Text(
                  'You have $pendingBugs pending reports to resolve.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: [
            _buildStatCard(
              icon: Icons.bug_report,
              label: 'Total Bug\nReports',
              value: totalBugs.toString(),
              color: Colors.blue,
              width: cardWidth,
            ),
            _buildStatCard(
              icon: Icons.check_circle,
              label: 'Resolved\nBugs',
              value: resolvedBugs.toString(),
              color: Colors.green,
              width: cardWidth,
            ),
            _buildStatCard(
              icon: Icons.warning,
              label: 'Pending\nBugs',
              value: pendingBugs.toString(),
              color: Colors.red,
              width: cardWidth,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
} 