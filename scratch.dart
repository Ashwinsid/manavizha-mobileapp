import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  // We don't have a full flutter environment to init Supabase easily from command line.
  // Wait, scratch.dart can't run Supabase.instance.client if it hasn't called Supabase.initialize().
  print('Need to find db schema');
}
