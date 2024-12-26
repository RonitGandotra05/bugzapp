import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screens/user_management_screen.dart';
import '../screens/project_management_screen.dart';

class AppDrawer extends StatelessWidget {
  final bool isAdmin;
  final VoidCallback onLogout;

  const AppDrawer({
    Key? key,
    required this.isAdmin,
    required this.onLogout,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.purple[50]!,
              Colors.purple[100]!,
            ],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.purple[400]!,
                    Colors.purple[700]!,
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bug_report,
                    size: 48,
                    color: Colors.white,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'BugZapp',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (isAdmin) ...[
              ListTile(
                leading: Icon(Icons.admin_panel_settings),
                title: Text(
                  'User Management',
                  style: GoogleFonts.poppins(),
                ),
                onTap: () {
                  Navigator.pop(context); // Close drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const UserManagementScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.folder_special),
                title: Text(
                  'Project Management',
                  style: GoogleFonts.poppins(),
                ),
                onTap: () {
                  Navigator.pop(context); // Close drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProjectManagementScreen(),
                    ),
                  );
                },
              ),
            ],
            ListTile(
              leading: Icon(Icons.logout),
              title: Text(
                'Logout',
                style: GoogleFonts.poppins(),
              ),
              onTap: () {
                Navigator.pop(context); // Close drawer
                onLogout();
              },
            ),
          ],
        ),
      ),
    );
  }
} 