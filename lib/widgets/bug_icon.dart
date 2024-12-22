import 'package:flutter/material.dart';

class BugIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const BugIcon({
    Key? key,
    required this.size,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.bug_report,
      size: size,
      color: color ?? Colors.white.withOpacity(0.9),
    );
  }
} 