import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'partner_home_screen.dart';
import 'user_home_screen.dart';

/// Routes the signed-in user to the correct home based on [admins] / [referral_partners].
/// Clears the stack (same as [LoginScreen] after successful sign-in).
Future<void> navigateToRoleHome(BuildContext context, String userId) async {
  final nav = Navigator.of(context);
  final client = Supabase.instance.client;

  try {
    final adminData = await client
        .from('admins')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();

    if (!context.mounted) return;
    if (adminData != null) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (context) => const AdminHomeScreen()),
        (route) => false,
      );
      return;
    }
  } catch (e, st) {
    debugPrint('navigateToRoleHome admins: $e\n$st');
  }

  try {
    final partnerData = await client
        .from('referral_partners')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();

    if (!context.mounted) return;
    if (partnerData != null) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (context) => const PartnerHomeScreen()),
        (route) => false,
      );
      return;
    }
  } catch (e, st) {
    debugPrint('navigateToRoleHome referral_partners: $e\n$st');
  }

  if (!context.mounted) return;
  nav.pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (context) => const UserHomeScreen()),
    (route) => false,
  );
}
