import 'package:flutter/material.dart';
import '../models/bug_filter.dart';
import '../models/bug_report.dart';

class BugFilterDialog extends StatefulWidget {
  final BugFilter initialFilter;
  final Function(BugFilter) onApply;

  const BugFilterDialog({
    Key? key,
    required this.initialFilter,
    required this.onApply,
  }) : super(key: key);

  @override
  _BugFilterDialogState createState() => _BugFilterDialogState();
}

class _BugFilterDialogState extends State<BugFilterDialog> {
  late BugFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filter Bugs'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Project filter
            TextField(
              decoration: const InputDecoration(labelText: 'Project'),
              controller: TextEditingController(text: _filter.project),
              onChanged: (value) {
                setState(() {
                  _filter = _filter.copyWith(project: value.isEmpty ? null : value);
                });
              },
            ),
            const SizedBox(height: 16),

            // Creator filter
            TextField(
              decoration: const InputDecoration(labelText: 'Creator'),
              controller: TextEditingController(text: _filter.creator),
              onChanged: (value) {
                setState(() {
                  _filter = _filter.copyWith(creator: value.isEmpty ? null : value);
                });
              },
            ),
            const SizedBox(height: 16),

            // Assignee filter
            TextField(
              decoration: const InputDecoration(labelText: 'Assignee'),
              controller: TextEditingController(text: _filter.assignee),
              onChanged: (value) {
                setState(() {
                  _filter = _filter.copyWith(assignee: value.isEmpty ? null : value);
                });
              },
            ),
            const SizedBox(height: 16),

            // Status filter
            DropdownButtonFormField<BugStatus>(
              decoration: const InputDecoration(labelText: 'Status'),
              value: _filter.status,
              items: BugStatus.values.map((status) {
                return DropdownMenuItem(
                  value: status,
                  child: Text(status.name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _filter = _filter.copyWith(status: value);
                });
              },
            ),
            const SizedBox(height: 16),

            // Severity filter
            DropdownButtonFormField<SeverityLevel>(
              decoration: const InputDecoration(labelText: 'Severity'),
              value: _filter.severity,
              items: SeverityLevel.values.map((severity) {
                return DropdownMenuItem(
                  value: severity,
                  child: Text(severity.name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _filter = _filter.copyWith(severity: value);
                });
              },
            ),
            const SizedBox(height: 16),

            // Created by me filter
            CheckboxListTile(
              title: const Text('Created by me'),
              value: _filter.createdByMe,
              onChanged: (value) {
                setState(() {
                  _filter = _filter.copyWith(createdByMe: value ?? false);
                });
              },
            ),

            // Assigned to me filter
            CheckboxListTile(
              title: const Text('Assigned to me'),
              value: _filter.assignedToMe,
              onChanged: (value) {
                setState(() {
                  _filter = _filter.copyWith(assignedToMe: value ?? false);
                });
              },
            ),

            // Sort options
            DropdownButtonFormField<BugSortOption>(
              decoration: const InputDecoration(labelText: 'Sort by'),
              value: _filter.sortBy,
              items: BugSortOption.values.map((option) {
                return DropdownMenuItem(
                  value: option,
                  child: Text(option.name),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _filter = _filter.copyWith(sortBy: value);
                });
              },
            ),

            // Ascending/Descending order
            CheckboxListTile(
              title: const Text('Ascending order'),
              value: _filter.ascending,
              onChanged: (value) {
                setState(() {
                  _filter = _filter.copyWith(ascending: value ?? false);
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onApply(_filter);
            Navigator.of(context).pop();
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
} 