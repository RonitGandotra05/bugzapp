import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'providers/bug_report_provider.dart';
import 'services/bug_report_service.dart';
import 'services/logging_service.dart';
import 'services/notification_service.dart';
import 'services/navigation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notification service
  await NotificationService().initialize();
  
  final logger = LoggingService();
  logger.info('Starting BugZapp application');
  
  final bugReportService = BugReportService();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => BugReportProvider(bugReportService),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NavigationService.navigatorKey,
      title: 'BugZapp',
      theme: ThemeData(
        primarySwatch: Colors.purple,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const SplashScreen(),
      onGenerateRoute: (settings) {
        if (settings.name == '/home') {
          final args = settings.arguments as Map<String, dynamic>?;
          final scrollToBugId = args?['scrollToBugId'] as int?;
          return MaterialPageRoute(
            builder: (context) => HomeScreen(initialBugId: scrollToBugId),
          );
        }
        return null;
      },
    );
  }
} 