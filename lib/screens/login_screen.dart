import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../utils/token_storage.dart';
import 'home_screen.dart';
import 'forgot_password_screen.dart';
import '../services/bug_report_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  
  // Mouse position for interactive background
  Offset _mousePosition = Offset.zero;

  // Add this to your state class:
  bool _isCardHovered = false;

  void _updateMousePosition(PointerEvent details) {
    setState(() {
      _mousePosition = details.localPosition;
    });
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final response = await _authService.login(
          _emailController.text,
          _passwordController.text,
        );

        if (response['access_token'] != null) {
          await TokenStorage.saveToken(response['access_token']);
          await TokenStorage.saveIsAdmin(response['is_admin'] ?? false);
          
          // Handle user_id more safely
          final userId = response['user_id'];
          if (userId != null) {
            await TokenStorage.saveUserId(userId);
          }

          final bugReportService = BugReportService();
          await bugReportService.loadAllComments();
          await bugReportService.initializeWebSocket(); // Initialize WebSocket after successful login

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Invalid credentials'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Login failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MouseRegion(
        onHover: (event) {
          if (!_isCardHovered) {  // Only update if not hovering over card
            setState(() {
              _mousePosition = event.localPosition;
            });
          }
        },
        child: Stack(
          children: [
            // Animated Background with smoother gradient
            AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: const [
                    Color(0xFFE9D5FF),  // Light purple/white blend
                    Color(0xFFD8B4FE),  // Lighter purple
                    Color(0xFFC084FC),  // Medium purple
                    Color(0xFFA855F7),  // Darker purple
                  ],
                  stops: const [0.0, 0.3, 0.6, 1.0],
                ),
              ),
              child: CustomPaint(
                painter: ShimmerPainter(_mousePosition),
                size: Size.infinite,
              ),
            ),
            
            // Login Form
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _isCardHovered = true),
                    onExit: (_) => setState(() => _isCardHovered = false),
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 200),
                      tween: Tween<double>(
                        begin: 0,
                        end: _isCardHovered ? 1 : 0,
                      ),
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, -8 * value), // Lift card up when hovered
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Card(
                              elevation: 20 + (10 * value), // Increase elevation on hover
                              shadowColor: Colors.black38,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  color: Colors.white.withOpacity(0.95),
                                  border: Border.all(
                                    color: Colors.white24,
                                    width: 1,
                                  ),
                                  boxShadow: _isCardHovered ? [
                                    BoxShadow(
                                      color: Colors.purple.withOpacity(0.1),
                                      blurRadius: 20,
                                      spreadRadius: 10,
                                    ),
                                  ] : [],
                                ),
                                padding: const EdgeInsets.all(32.0),
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Logo
                                      Image.network(
                                        'https://crmremarks.s3.ap-south-1.amazonaws.com/icon.png',
                                        height: 80,
                                        width: 80,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return SizedBox(
                                            height: 80,
                                            width: 80,
                                            child: Center(
                                              child: CircularProgressIndicator(
                                                value: loadingProgress.expectedTotalBytes != null
                                                    ? loadingProgress.cumulativeBytesLoaded /
                                                        loadingProgress.expectedTotalBytes!
                                                    : null,
                                              ),
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return const Icon(Icons.bug_report, size: 80);
                                        },
                                      ),
                                      const SizedBox(height: 24),
                                      Text(
                                        'Sign In',
                                        style: GoogleFonts.poppins(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Use the account below to sign in.',
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 32),
                                      TextFormField(
                                        controller: _emailController,
                                        decoration: InputDecoration(
                                          labelText: 'Email',
                                          prefixIcon: const Icon(Icons.email_outlined),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide(color: Colors.grey[300]!),
                                          ),
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter your email';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      TextFormField(
                                        controller: _passwordController,
                                        obscureText: _obscurePassword,
                                        decoration: InputDecoration(
                                          labelText: 'Password',
                                          prefixIcon: const Icon(Icons.lock_outline),
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_off
                                                  : Icons.visibility,
                                              color: Colors.grey[600],
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _obscurePassword = !_obscurePassword;
                                              });
                                            },
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide(color: Colors.grey[300]!),
                                          ),
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter your password';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 8),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => const ForgotPasswordScreen(),
                                              ),
                                            );
                                          },
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                          ),
                                          child: Text(
                                            'Forgot Password?',
                                            style: GoogleFonts.poppins(
                                              color: const Color(0xFF7C3AED),
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      SizedBox(
                                        height: 48,
                                        child: ElevatedButton(
                                          onPressed: _isLoading ? null : _handleLogin,
                                          style: ElevatedButton.styleFrom(
                                            // Metallic purple gradient background
                                            backgroundColor: Colors.transparent,
                                            foregroundColor: Colors.white,  // Text and icon color
                                            elevation: 8,
                                            shadowColor: Colors.purple.withOpacity(0.5),
                                            padding: EdgeInsets.zero,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ).copyWith(
                                            backgroundColor: MaterialStateProperty.resolveWith<Color>(
                                              (Set<MaterialState> states) {
                                                if (states.contains(MaterialState.pressed)) {
                                                  return const Color(0xFF9333EA);  // Darker when pressed
                                                }
                                                return const Color(0xFFA855F7);  // Default metallic purple
                                              },
                                            ),
                                            overlayColor: MaterialStateProperty.all(
                                              Colors.white.withOpacity(0.1),  // Subtle highlight on hover
                                            ),
                                          ),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                              gradient: const LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Color(0xFFA855F7),  // Metallic purple
                                                  Color(0xFF9333EA),  // Slightly darker purple
                                                ],
                                              ),
                                            ),
                                            child: Center(
                                              child: _isLoading
                                                  ? const SizedBox(
                                                      width: 24,
                                                      height: 24,
                                                      child: CircularProgressIndicator(
                                                        color: Colors.white,
                                                        strokeWidth: 2,
                                                      ),
                                                    )
                                                  : Text(
                                                      'Login',
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w600,
                                                        color: Colors.white,  // Explicitly white text
                                                        letterSpacing: 0.5,  // Slight letter spacing for better readability
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

// Custom painter for metallic shimmer effect
class ShimmerPainter extends CustomPainter {
  final Offset mousePosition;

  ShimmerPainter(this.mousePosition);

  @override
  void paint(Canvas canvas, Size size) {
    // Background gradient
    final backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(0.1),
          const Color(0xFFE9D5FF).withOpacity(0.1),  // Very light purple
          const Color(0xFFA855F7).withOpacity(0.2),  // Purple
        ],
      ).createShader(Offset.zero & size);

    // Shimmer effect
    final shimmerPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          (mousePosition.dx / size.width) * 2 - 1,
          (mousePosition.dy / size.height) * 2 - 1,
        ),
        radius: 0.15, // Even smaller radius for more subtle effect
        colors: [
          Colors.white.withOpacity(0.07),  // Very subtle white shimmer
          Colors.transparent,
        ],
        stops: const [0.0, 1.0],
      ).createShader(Offset.zero & size);

    // Draw layers
    canvas.drawRect(Offset.zero & size, backgroundPaint);
    canvas.drawRect(Offset.zero & size, shimmerPaint);
  }

  @override
  bool shouldRepaint(ShimmerPainter oldDelegate) =>
      oldDelegate.mousePosition != mousePosition;
} 