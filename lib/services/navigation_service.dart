import 'package:flutter/material.dart';
import '../screens/home_screen.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static void navigateToBug(int bugId) {
    if (navigatorKey.currentState != null) {
      // If app is not running or in background, launch it and navigate
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      if (lifecycleState == null || lifecycleState == AppLifecycleState.paused || lifecycleState == AppLifecycleState.detached) {
        navigatorKey.currentState!.pushNamedAndRemoveUntil(
          '/home',
          (route) => false,
          arguments: {'scrollToBugId': bugId},
        );
      } else {
        // If app is running, just scroll to the bug
        final context = navigatorKey.currentContext;
        if (context != null) {
          // Find the nearest HomeScreen and call scrollToBug
          HomeScreenState? homeScreen = context.findAncestorStateOfType<HomeScreenState>();
          homeScreen?.scrollToBugCard(bugId);
        }
      }
    }
  }
} 