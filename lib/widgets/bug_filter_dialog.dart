import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/bug_report.dart';
import '../models/bug_filter.dart';

class BugFilterDialog extends StatefulWidget {
  final BugFilter currentFilter;
  final List<String> projects;
  final List<String> creators;
  final List<String> assignees;

  const BugFilterDialog({
    Key? key,
    required this.currentFilter,
    required this.projects,
    required this.creators,
    required this.assignees,
  }) : super(key: key);

  @override
  State<BugFilterDialog> createState() => _BugFilterDialogState();
}

class _BugFilterDialogState extends State<BugFilterDialog> {
  late BugFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.currentFilter;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filter Bugs',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Project Dropdown
            if (widget.projects.isNotEmpty) ...[
              _buildDropdown(
                'Project',
                widget.projects,
                _filter.project,
                (value) => setState(() {
                  _filter = _filter.copyWith(project: value);
                }),
              ),
              const SizedBox(height: 12),
            ],

            // Creator Dropdown
            if (widget.creators.isNotEmpty) ...[
              _buildDropdown(
                'Creator',
                widget.creators,
                _filter.creator,
                (value) => setState(() {
                  _filter = _filter.copyWith(creator: value);
                }),
              ),
              const SizedBox(height: 12),
            ],

            // Assignee Dropdown
            if (widget.assignees.isNotEmpty) ...[
              _buildDropdown(
                'Assignee',
                widget.assignees,
                _filter.assignee,
                (value) => setState(() {
                  _filter = _filter.copyWith(assignee: value);
                }),
              ),
              const SizedBox(height: 12),
            ],

            // Status Dropdown
            _buildDropdown<BugStatus>(
              'Status',
              BugStatus.values,
              _filter.status,
              (value) => setState(() {
                _filter = _filter.copyWith(status: value);
              }),
              labelFunc: (status) => status.toString().split('.').last.toUpperCase(),
            ),
            const SizedBox(height: 12),

            // Severity Dropdown
            _buildDropdown<SeverityLevel>(
              'Severity',
              SeverityLevel.values,
              _filter.severity,
              (value) => setState(() {
                _filter = _filter.copyWith(severity: value);
              }),
              labelFunc: (severity) => severity.toString().split('.').last.toUpperCase(),
            ),
            const SizedBox(height: 12),

            // Sort Options
            _buildDropdown<BugSortOption>(
              'Sort By',
              BugSortOption.values,
              _filter.sortBy,
              (value) => setState(() {
                _filter = _filter.copyWith(sortBy: value);
              }),
              labelFunc: (option) => option.toString().split('.').last
                  .replaceAll(RegExp(r'(?=[A-Z])'), ' ')
                  .toUpperCase(),
            ),
            const SizedBox(height: 8),

            // Sort Direction
            SwitchListTile(
              title: Text(
                'Ascending Order',
                style: GoogleFonts.poppins(),
              ),
              value: _filter.ascending,
              onChanged: (value) {
                setState(() {
                  _filter = _filter.copyWith(ascending: value);
                });
              },
            ),

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.poppins(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _filter),
                  child: Text(
                    'Apply',
                    style: GoogleFonts.poppins(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown<T>(
    String label,
    List<T> items,
    T? value,
    void Function(T?) onChanged, {
    String Function(T)? labelFunc,
  }) {
    return DropdownButtonFormField<T>(
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      value: value,
      items: [
        const DropdownMenuItem(
          value: null,
          child: Text('All'),
        ),
        ...items.map((item) => DropdownMenuItem(
              value: item,
              child: Text(labelFunc?.call(item) ?? item.toString()),
            )),
      ],
      onChanged: onChanged,
    );
  }
} 