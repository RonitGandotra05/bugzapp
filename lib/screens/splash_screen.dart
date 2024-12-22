import 'package:flutter/material.dart';
import '../utils/token_storage.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/bug_icon.dart';

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
      body: MouseRegion(
        onHover: (event) => setState(() => _mousePosition = event.localPosition),
        child: CustomPaint(
          painter: ShimmerPainter(_mousePosition),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BugIcon(size: 120),
                const SizedBox(height: 24),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'BugzApp',
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
                          Colors.purple.shade300,
                          Colors.purple.shade500,
                          Colors.purple.shade300,
                        ],
                      ).createShader(bounds),
                      child: Text(
                        'BugzApp',
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