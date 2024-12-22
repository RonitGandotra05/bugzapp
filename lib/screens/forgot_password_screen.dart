import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({Key? key}) : super(key: key);

  @override
  _ForgotPasswordScreenState createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _otpSent = false;
  Offset _mousePosition = Offset.zero;
  bool _isCardHovered = false;
  bool _obscurePassword = true;

  Future<void> _sendOTP() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    
    try {
      await _authService.requestPasswordReset(_emailController.text);
      
      if (mounted) {
        setState(() {
          _otpSent = true;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OTP sent to your email'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    
    try {
      await _authService.resetPassword(
        _emailController.text,
        _otpController.text,
        _newPasswordController.text,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset successful'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MouseRegion(
        onHover: (event) {
          if (!_isCardHovered) {
            setState(() {
              _mousePosition = event.localPosition;
            });
          }
        },
        child: Stack(
          children: [
            // Animated Background
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

            // Back Button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.black87),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),

            // Main Content
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
                          offset: Offset(0, -8 * value),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Card(
                              elevation: 20 + (10 * value),
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
                                          return const SizedBox(
                                            height: 80,
                                            width: 80,
                                            child: Center(child: CircularProgressIndicator()),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          return const Icon(Icons.bug_report, size: 80);
                                        },
                                      ),
                                      const SizedBox(height: 24),
                                      Text(
                                        'Forgot Password',
                                        style: GoogleFonts.poppins(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _otpSent 
                                          ? 'Enter OTP and new password'
                                          : 'Enter your email address',
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
                                      if (_otpSent) ...[
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: _otpController,
                                          decoration: InputDecoration(
                                            labelText: 'OTP',
                                            prefixIcon: const Icon(Icons.security),
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
                                              return 'Please enter the OTP';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 16),
                                        TextFormField(
                                          controller: _newPasswordController,
                                          obscureText: _obscurePassword,
                                          decoration: InputDecoration(
                                            labelText: 'New Password',
                                            prefixIcon: const Icon(Icons.lock_outline),
                                            suffixIcon: IconButton(
                                              icon: Icon(
                                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
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
                                              return 'Please enter new password';
                                            }
                                            return null;
                                          },
                                        ),
                                      ],
                                      const SizedBox(height: 24),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 48,
                                        child: ElevatedButton(
                                          onPressed: _isLoading ? null : (_otpSent ? _resetPassword : _sendOTP),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            foregroundColor: Colors.white,
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
                                                  return const Color(0xFF9333EA);
                                                }
                                                return const Color(0xFFA855F7);
                                              },
                                            ),
                                            overlayColor: MaterialStateProperty.all(
                                              Colors.white.withOpacity(0.1),
                                            ),
                                          ),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                              gradient: const LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Color(0xFFA855F7),
                                                  Color(0xFF9333EA),
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
                                                      _otpSent ? 'Reset Password' : 'Send OTP',
                                                      style: GoogleFonts.poppins(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w600,
                                                        color: Colors.white,
                                                        letterSpacing: 0.5,
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
    _otpController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }
}

// Copy the ShimmerPainter from LoginScreen
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