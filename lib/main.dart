import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://olktibxfpgfjkcppqbqd.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9sa3RpYnhmcGdmamtjcHBxYnFkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM5MDM0NzMsImV4cCI6MjA3OTQ3OTQ3M30.2z45yGrwKzRN4Ko1hPA9rhC3ukIlf4dwceUyYag1JHM',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Manavizha App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Satoshi',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6A11CB)),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
