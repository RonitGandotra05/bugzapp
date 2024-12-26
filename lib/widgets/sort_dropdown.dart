import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SortDropdown extends StatelessWidget {
  final String value;
  final bool ascending;
  final Function(String?) onChanged;

  const SortDropdown({
    Key? key,
    required this.value,
    required this.ascending,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sort by:',
          style: GoogleFonts.poppins(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: value,
          underline: Container(
            height: 2,
            color: Colors.purple[400],
          ),
          style: GoogleFonts.poppins(
            color: Colors.purple[700],
            fontWeight: FontWeight.w500,
          ),
          onChanged: onChanged,
          items: [
            DropdownMenuItem(
              value: 'date',
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16),
                  const SizedBox(width: 8),
                  Text('Date ${ascending ? '↑' : '↓'}'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'severity',
              child: Row(
                children: [
                  const Icon(Icons.warning, size: 16),
                  const SizedBox(width: 8),
                  Text('Severity ${ascending ? '↑' : '↓'}'),
                ],
              ),
            ),
            DropdownMenuItem(
              value: 'status',
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 16),
                  const SizedBox(width: 8),
                  Text('Status ${ascending ? '↑' : '↓'}'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
} 