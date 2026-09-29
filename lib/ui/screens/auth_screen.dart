// lib/ui/screens/auth_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

class AuthScreen extends StatefulWidget {
  final AuthService authService;

  const AuthScreen({super.key, required this.authService});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSignUp = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await action();
    } on fb.FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Authentication failed');
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        setState(() => _errorMessage = 'Google sign-in failed: ${e.code.name}');
      }
    } catch (e) {
      setState(() => _errorMessage = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitEmailPassword() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    await _runAuth(() => _isSignUp
        ? widget.authService.signUpWithEmail(email: email, password: password)
        : widget.authService.signInWithEmail(email: email, password: password));
  }

  Future<void> _signInWithGoogle() =>
      _runAuth(widget.authService.signInWithGoogle);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xxxl),

                // ---- Brand block ----
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield,
                      color: AppColors.primary,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'SafeSignal',
                  textAlign: TextAlign.center,
                  style: text.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Your silence is your signal',
                  textAlign: TextAlign.center,
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxxl),

                // ---- Google sign-in ----
                _GoogleSignInButton(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  busy: _isLoading,
                ),
                const SizedBox(height: AppSpacing.xl),

                // ---- Divider ----
                Row(
                  children: [
                    Expanded(child: Divider(color: scheme.outlineVariant)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md),
                      child: Text(
                        'or',
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    Expanded(child: Divider(color: scheme.outlineVariant)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // ---- Email / password ----
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email required';
                    if (!v.contains('@')) return 'Invalid email';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password required';
                    if (v.length < 6) return 'Min 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                if (_errorMessage != null) ...[
                  AppCard(
                    background: scheme.errorContainer,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            size: 20, color: scheme.onErrorContainer),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: text.bodySmall
                                ?.copyWith(color: scheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                PrimaryButton(
                  label: _isSignUp ? 'Create account' : 'Sign in',
                  onPressed: _submitEmailPassword,
                  busy: _isLoading,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => setState(() {
                    _isSignUp = !_isSignUp;
                    _errorMessage = null;
                  }),
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign in'
                        : "Don't have an account? Sign up",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// GOOGLE SIGN-IN BUTTON
// ============================================================================
//
// Follows Google's brand guidelines for the "Sign in with Google" button:
//   - White background, 1dp neutral border
//   - Multi-color "G" logo on the left
//   - Roboto/system font, "Sign in with Google" text
//   - Same 56dp height as other primary CTAs for visual consistency

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.onPressed,
    required this.busy,
  });

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppTouchTargets.primary,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          side: const BorderSide(color: Color(0xFFDADCE0), width: 1),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
        child: busy
            ? const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            _GoogleLogo(size: 20),
            SizedBox(width: AppSpacing.md),
            Text(
              'Sign in with Google',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F1F1F),
                letterSpacing: 0.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Google "G" logo as inline widget — avoids bundling an SVG or asset.
/// The four colored arcs are approximated with a stacked layout that
/// reads correctly at button sizes (18-24dp).
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    // Use the Material icon fallback approach: a stylized "G" via text
    // with the Google blue. For a production app, swap this for the
    // official multi-color SVG from Google's brand assets.
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

/// Minimalist multi-color Google "G" drawn with Canvas. Approximates the
/// official logo well enough at button sizes without needing an asset.
class _GoogleGPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2;
    final strokeWidth = size.width * 0.22;
    final r = radius - strokeWidth / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Blue: right side (roughly -20° to 90°)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      _rad(-20), _rad(110), false,
      paint..color = _blue,
    );
    // Green: bottom-right (90° to 200°)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      _rad(90), _rad(70), false,
      paint..color = _green,
    );
    // Yellow: bottom-left (160° to 250°)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      _rad(160), _rad(70), false,
      paint..color = _yellow,
    );
    // Red: top (230° to 340°)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      _rad(230), _rad(110), false,
      paint..color = _red,
    );

    // Horizontal bar of the "G" (right side, blue)
    final barPaint = Paint()..color = _blue;
    final barRect = Rect.fromLTWH(
      center.dx,
      center.dy - strokeWidth / 2,
      radius - strokeWidth / 2,
      strokeWidth,
    );
    canvas.drawRect(barRect, barPaint);
  }

  double _rad(double deg) => deg * 3.1415926535 / 180;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}