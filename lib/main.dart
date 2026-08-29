import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'splash_screen.dart';
import 'update_password_screen.dart';

/// Supabase auth redirect used by password-reset and email-verification
/// emails. Must be listed in Supabase Auth → URL Configuration → Redirect
/// URLs, and matches the intent-filter / CFBundleURLTypes platform config.
const String kAuthRedirectUrl = 'manavizha://auth-callback';

final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://olktibxfpgfjkcppqbqd.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9sa3RpYnhmcGdmamtjcHBxYnFkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM5MDM0NzMsImV4cCI6MjA3OTQ3OTQ3M30.2z45yGrwKzRN4Ko1hPA9rhC3ukIlf4dwceUyYag1JHM',
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // Password-reset deep link: supabase_flutter processes the incoming
    // manavizha://auth-callback URI and emits passwordRecovery — surface the
    // set-new-password screen (mobile counterpart of the web's
    // /account/update-password page).
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute<void>(builder: (_) => const UpdatePasswordScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      title: 'Manavizha App',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        fontFamily: 'Satoshi',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2FA086)),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
