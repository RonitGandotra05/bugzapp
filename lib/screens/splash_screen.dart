import 'package:flutter/material.dart';
import '../utils/token_storage.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/bug_icon.dart';
import '../services/bug_report_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Offset _mousePosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2)); // Add a small delay for animation
    final isLoggedIn = await TokenStorage.isLoggedIn();
    
    if (isLoggedIn) {
      print('[Splash] User is logged in, initializing services...');
      // Initialize services before navigating to home screen
      final bugReportService = BugReportService();
      
      print('[Splash] Initializing WebSocket connection...');
      await bugReportService.initializeWebSocket();
      
      print('[Splash] Loading initial data...');
      await bugReportService.loadAllComments();
    }
    
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => isLoggedIn ? const HomeScreen() : const LoginScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF9575CD),  // Deeper purple
              Color(0xFF7E57C2),  // Medium-deep purple
              Color(0xFF673AB7),  // Dark purple
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Bug Icon with glow effect
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const BugIcon(
                  size: 72,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              
              // App Name with shimmer effect
              Stack(
                alignment: Alignment.center,
                children: [
                  Text(
                    'BugZapp',
                    style: GoogleFonts.poppins(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 12
                        ..color = Colors.purple.withOpacity(0.2),
                      shadows: [
                        BoxShadow(
                          color: Colors.purple.withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                  ),
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.9),
                        Colors.white,
                        Colors.white.withOpacity(0.9),
                      ],
                    ).createShader(bounds),
                    child: Text(
                      'BugZapp',
                      style: GoogleFonts.poppins(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShimmerPainter extends CustomPainter {
  final Offset mousePosition;

  ShimmerPainter(this.mousePosition);

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.1),
          const Color(0xFFE9D5FF).withOpacity(0.1),
          const Color(0xFFA855F7).withOpacity(0.2),
        ],
      ).createShader(Offset.zero & size);

    final shimmerPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (mousePosition.dx / size.width) * 2 - 1,
          (mousePosition.dy / size.height) * 2 - 1,
        ),
        radius: 0.15,
        colors: [
          Colors.white.withOpacity(0.07),
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, backgroundPaint);
    canvas.drawRect(Offset.zero & size, shimmerPaint);
  }

  @override
  bool shouldRepaint(ShimmerPainter oldDelegate) =>
      oldDelegate.mousePosition != mousePosition;
} 