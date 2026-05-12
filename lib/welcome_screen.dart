import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'partner_landing_screen.dart';
import 'signup_screen.dart';

/// Brand teal — keep in sync with [splash_screen.dart] and [main.dart].
const Color _kBrand = Color(0xFF2FA086);

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FBF9),
      body: Container(
        decoration: const BoxDecoration(
          // Same multi-stop gradient as the splash screen so the brand surface
          // flows seamlessly from launch into the welcome experience.
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
        child: Stack(
          children: [
            // Subtle decorative motifs to keep the matrimony theme.
            Positioned(
              top: 80,
              left: -30,
              child: Icon(
                Icons.favorite,
                color: Colors.pinkAccent.withValues(alpha: 0.05),
                size: 180,
              ),
            ),
            Positioned(
              top: 300,
              right: -50,
              child: Icon(
                Icons.favorite,
                color: _kBrand.withValues(alpha: 0.05),
                size: 250,
              ),
            ),
            Positioned(
              bottom: 150,
              left: 20,
              child: Icon(
                Icons.star_rounded,
                color: Colors.amber.withValues(alpha: 0.10),
                size: 60,
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(height: 10),

                    // Top section — logo + interlocking rings + headline.
                    Column(
                      children: [
                        Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _kBrand.withValues(alpha: 0.18),
                                blurRadius: 28,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18.0),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Interlocking rings symbolizing marriage.
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.translate(
                              offset: const Offset(-18, 0),
                              child: Container(
                                width: 55,
                                height: 55,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFFFD700),
                                    width: 4,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFD700)
                                          .withValues(alpha: 0.30),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(18, 0),
                              child: Container(
                                width: 55,
                                height: 55,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFF39C12),
                                    width: 4,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFF39C12)
                                          .withValues(alpha: 0.30),
                                      blurRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        const Text(
                          "Find Your Soulmate",
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E1E1E),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "Join Manavizha to discover your perfect match and begin a beautifully blessed journey together.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black54,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),

                    // Bottom section — action buttons.
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () async {
                              final email =
                                  await Navigator.of(context).push<String>(
                                MaterialPageRoute(
                                  builder: (context) => const SignupScreen(),
                                ),
                              );
                              if (!context.mounted) return;
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) =>
                                      LoginScreen(initialEmail: email),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kBrand,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                              shadowColor: _kBrand.withValues(alpha: 0.4),
                            ),
                            child: const Text(
                              'Create an Account',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const LoginScreen(),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _kBrand,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.55),
                              side: const BorderSide(
                                color: _kBrand,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Log In to Existing Account',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const PartnerLandingScreen(),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.handshake_rounded,
                            color: Color(0xFF4B0082),
                          ),
                          label: const Text(
                            'Become a referral partner',
                            style: TextStyle(
                              color: Color(0xFF4B0082),
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
