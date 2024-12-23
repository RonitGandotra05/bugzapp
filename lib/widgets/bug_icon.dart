import 'package:flutter/material.dart';

class BugIcon extends StatelessWidget {
  final double size;
  final Color? color;

  const BugIcon({
    Key? key,
    this.size = 72.0,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Icon(
        Icons.bug_report,
        size: size,
        color: color ?? Colors.white.withOpacity(0.95),
      ),
    );
  }
} 