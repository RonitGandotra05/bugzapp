import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/splash_screen.dart';
import 'providers/bug_report_provider.dart';
import 'services/logging_service.dart';

void main() {
  final logger = LoggingService();
  logger.info('Starting BugZapp application');
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BugReportProvider()),
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
      title: 'BugZapp',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
} 