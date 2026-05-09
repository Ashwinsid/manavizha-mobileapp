import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_navigation.dart';
import 'welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// Brand teal — keep in sync with [main.dart] seed color.
const Color _kSplashBrand = Color(0xFF2FA086);

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  /// Three pulse rings staggered across the first phase.
  late Animation<double> _ring1;
  late Animation<double> _ring2;
  late Animation<double> _ring3;

  /// Logo only fades in after the ring effect has played most of the way through.
  late Animation<double> _logoOpacity;
  late Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();

    // Phase 1 (rings):  0.00 – 0.55  → ~1320 ms
    // Phase 2 (logo) :  0.50 – 0.95  → ~1080 ms (overlaps tail of phase 1 by 120 ms for smoothness)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    Animation<double> ring(double start) => CurvedAnimation(
          parent: _controller,
          curve: Interval(start, start + 0.45, curve: Curves.easeOutCubic),
        );
    _ring1 = ring(0.00);
    _ring2 = ring(0.10);
    _ring3 = ring(0.20);

    _logoOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.50, 0.95, curve: Curves.easeIn),
    );
    _logoScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.50, 0.95, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();

    // After splash, route to role home if a session was restored, else welcome.
    // Wait for animation to finish (2400ms) plus a short hold (~1100ms) so the logo is fully visible.
    Future<void> goNext() async {
      await Future<void>.delayed(const Duration(milliseconds: 3500));
      if (!mounted) return;

      Session? session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          session = Supabase.instance.client.auth.currentSession;
          if (session != null) break;
        }
      }

      if (!mounted) return;

      if (session != null) {
        await navigateToRoleHome(context, session.user.id);
        return;
      }

      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (context, animation, secondaryAnimation) => const WelcomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    }

    goNext();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Light multi-stop gradient — bright white flowing into a clearly visible mint at the far corner.
    return Scaffold(
      backgroundColor: const Color(0xFFF5FBF9),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.55, 1.0],
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFD8F2EA),
              Color(0xFF9BDDC9),
            ],
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Center(
              child: SizedBox(
                width: 360,
                height: 360,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _PulseRing(progress: _ring1.value),
                    _PulseRing(progress: _ring2.value),
                    _PulseRing(progress: _ring3.value),
                    Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: SizedBox(
                          width: 240,
                          height: 240,
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Single expanding teal ring — grows from a small dot to ~340 px while fading out.
///
/// [progress] runs 0 → 1 over the ring's animation interval. Outside that range nothing is drawn.
class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0 || progress >= 1) return const SizedBox.shrink();
    final double size = 80 + 280 * progress;
    final double alpha = (1.0 - progress) * 0.55;
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _kSplashBrand.withValues(alpha: alpha),
            width: 2.5,
          ),
        ),
      ),
    );
  }
}
