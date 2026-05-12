import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'partner_home_screen.dart';

/// Flutter port of `manavizha/components/referral-partner-auth-dialog.tsx`.
///
/// A modal sheet that drives partner authentication from the partner landing
/// screen. Two modes:
///   * **Login** — `signInWithPassword` + verify the user exists in
///     `referral_partners` (signs out if not, mirroring the web rejection).
///   * **Sign up** — `signUp` + `upsert` a `referral_partners` row keyed by
///     `user_id`, then flip back to Login with the email pre-filled.
///
/// Password rules mirror the web component exactly: minimum 11 characters,
/// lowercase + uppercase, at least one digit, at least one symbol.
class PartnerAuthDialog extends StatefulWidget {
  const PartnerAuthDialog({super.key, this.initialMode = PartnerAuthMode.login});

  final PartnerAuthMode initialMode;

  @override
  State<PartnerAuthDialog> createState() => _PartnerAuthDialogState();
}

/// Convenience wrapper — opens the dialog and returns `true` if a session was
/// created (so the calling landing screen can push the partner home).
Future<bool> showPartnerAuthDialog(
  BuildContext context, {
  bool startInSignup = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => PartnerAuthDialog(
      initialMode: startInSignup ? PartnerAuthMode.signup : PartnerAuthMode.login,
    ),
  );
  return result == true;
}

enum PartnerAuthMode { login, signup }

class _PartnerAuthDialogState extends State<PartnerAuthDialog> {
  static const Color _brand = AdminHomeScreen.brandPurple;

  late PartnerAuthMode _mode;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  _PasswordStrength get _strength {
    final pwd = _passCtrl.text;
    if (pwd.isEmpty) {
      return _PasswordStrength('', 0, Colors.grey.shade300, valid: false);
    }
    final hasMin = pwd.length >= 11;
    final hasLower = RegExp(r'[a-z]').hasMatch(pwd);
    final hasUpper = RegExp(r'[A-Z]').hasMatch(pwd);
    final hasDigit = RegExp(r'\d').hasMatch(pwd);
    final hasSymbol = RegExp(r'[^A-Za-z0-9]').hasMatch(pwd);
    final criteria = [hasMin, hasLower, hasUpper, hasDigit, hasSymbol].where((b) => b).length;
    if (!hasMin || criteria < 5) {
      return _PasswordStrength('Does not meet requirements', 0.30, Colors.red.shade500, valid: false);
    }
    if (pwd.length >= 14) {
      return _PasswordStrength('Strong password', 1.0, Colors.green.shade600, valid: true);
    }
    return _PasswordStrength('Meets minimum requirements', 0.7, Colors.amber.shade600, valid: true);
  }

  bool get _passwordsMatch {
    if (_mode == PartnerAuthMode.login) return true;
    if (_confirmCtrl.text.isEmpty) return true;
    return _passCtrl.text == _confirmCtrl.text;
  }

  bool get _canSubmit {
    if (_busy) return false;
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) return false;
    if (_mode == PartnerAuthMode.signup) {
      if (!_strength.valid) return false;
      if (!_passwordsMatch) return false;
      if (_confirmCtrl.text.isEmpty) return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });

    final client = Supabase.instance.client;
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    try {
      if (_mode == PartnerAuthMode.signup) {
        final res = await client.auth.signUp(email: email, password: password);
        final user = res.user;
        if (user == null) {
          throw AuthException('Sign-up did not return a session. Please try again.');
        }
        try {
          await client.from('referral_partners').upsert(
            {
              'user_id': user.id,
              'email': user.email,
            },
            onConflict: 'user_id',
          );
        } catch (e) {
          debugPrint('Partner upsert (non-fatal): $e');
        }
        if (!mounted) return;
        setState(() {
          _mode = PartnerAuthMode.login;
          _passCtrl.clear();
          _confirmCtrl.clear();
          _busy = false;
          _success = 'Account created. Sign in to continue.';
        });
        return;
      }

      // Login.
      final res = await client.auth.signInWithPassword(email: email, password: password);
      final user = res.user;
      if (user == null) throw AuthException('Could not sign in. Please try again.');

      final row = await client
          .from('referral_partners')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (row == null) {
        await client.auth.signOut();
        throw AuthException(
          'Access denied. This account is not registered as a referral partner.',
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const PartnerHomeScreen()),
        (_) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final wide = media.size.width >= 720;

    final card = Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _heroPanel()),
                  Expanded(child: _formPanel()),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _heroPanel(short: true),
                    _formPanel(),
                  ],
                ),
              ),
      ),
    );

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: wide ? 32 : 14,
        vertical: 24,
      ),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? 880 : double.infinity,
          maxHeight: media.size.height - 80,
        ),
        child: card,
      ),
    );
  }

  Widget _heroPanel({bool short = false}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F4068), Color(0xFF4B0082), Color(0xFFFF1493), Color(0xFFFFA500)],
          stops: [0.0, 0.35, 0.7, 1.0],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: short ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Text(
            'WELCOME BACK',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 4,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Partner with us to help create meaningful connections.',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Sign in to access your referral partner dashboard, track referrals and manage your account.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.4,
            ),
          ),
          if (!short) const Spacer(),
          if (!short) const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text('M', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 18)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Trusted Partner Network',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                    Text('Secure. Verified. Confidential.',
                        style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formPanel() {
    final isLogin = _mode == PartnerAuthMode.login;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isLogin ? 'Welcome back, Partner' : 'Become a Partner',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
          ),
          const SizedBox(height: 4),
          Text(
            isLogin
                ? 'Sign in to access your partner dashboard.'
                : 'Join our referral partner network and start earning.',
            style: TextStyle(fontSize: 13, color: Colors.black.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 14),
          _modeToggle(),
          const SizedBox(height: 14),
          if (_error != null) _banner(_error!, Colors.red.shade600, Colors.red.shade50, Icons.error_outline_rounded),
          if (_success != null) _banner(_success!, Colors.green.shade700, Colors.green.shade50, Icons.check_circle_rounded),
          const SizedBox(height: 4),
          _label('Email'),
          TextField(
            controller: _emailCtrl,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() => _error = null),
            decoration: _fieldDeco(hint: 'you@email.com'),
          ),
          const SizedBox(height: 12),
          _label('Password'),
          TextField(
            controller: _passCtrl,
            enabled: !_busy,
            obscureText: !_showPassword,
            onChanged: (_) => setState(() => _error = null),
            decoration: _fieldDeco(
              hint: '••••••••',
              suffixIcon: IconButton(
                icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          if (!isLogin && _passCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            _strengthBox(),
          ],
          if (!isLogin) ...[
            const SizedBox(height: 12),
            _label('Confirm password'),
            TextField(
              controller: _confirmCtrl,
              enabled: !_busy,
              obscureText: !_showConfirm,
              onChanged: (_) => setState(() => _error = null),
              decoration: _fieldDeco(
                hint: 'Repeat password',
                suffixIcon: IconButton(
                  icon: Icon(_showConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                  onPressed: () => setState(() => _showConfirm = !_showConfirm),
                ),
              ),
            ),
            if (_confirmCtrl.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    _passwordsMatch ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    size: 14,
                    color: _passwordsMatch ? Colors.green.shade600 : Colors.red.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _passwordsMatch ? 'Passwords match' : 'Passwords do not match',
                    style: TextStyle(
                      fontSize: 12,
                      color: _passwordsMatch ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF111827),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: _busy
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        const SizedBox(width: 10),
                        Text(isLogin ? 'Signing in…' : 'Creating account…',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                      ],
                    )
                  : Text(
                      isLogin ? 'Continue' : 'Create account',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.5)),
              children: const [
                TextSpan(text: 'By continuing, you agree to our '),
                TextSpan(text: 'Terms of Service', style: TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w700)),
                TextSpan(text: ' and '),
                TextSpan(text: 'Privacy Policy', style: TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w700)),
                TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _modeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        children: [
          Expanded(child: _toggleBtn('Login', _mode == PartnerAuthMode.login, () => _setMode(PartnerAuthMode.login))),
          Expanded(child: _toggleBtn('Sign up', _mode == PartnerAuthMode.signup, () => _setMode(PartnerAuthMode.signup))),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF111827) : Colors.transparent,
          borderRadius: BorderRadius.circular(40),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : Colors.black.withValues(alpha: 0.6),
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  void _setMode(PartnerAuthMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _error = null;
      _success = null;
      _passCtrl.clear();
      _confirmCtrl.clear();
    });
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  InputDecoration _fieldDeco({String? hint, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _brand, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      suffixIcon: suffixIcon,
    );
  }

  Widget _banner(String text, Color fg, Color bg, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: fg.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                text,
                style: TextStyle(fontSize: 12, color: fg, height: 1.4, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _strengthBox() {
    final pwd = _passCtrl.text;
    final s = _strength;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Password strength',
                  style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.55))),
              Text(s.label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: s.value,
              minHeight: 5,
              backgroundColor: Colors.black.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation<Color>(s.color),
            ),
          ),
          const SizedBox(height: 8),
          _ruleRow('Minimum 11 characters', pwd.length >= 11),
          _ruleRow('Lowercase & uppercase letters',
              RegExp(r'[a-z]').hasMatch(pwd) && RegExp(r'[A-Z]').hasMatch(pwd)),
          _ruleRow('At least one number', RegExp(r'\d').hasMatch(pwd)),
          _ruleRow('At least one symbol', RegExp(r'[^A-Za-z0-9]').hasMatch(pwd)),
        ],
      ),
    );
  }

  Widget _ruleRow(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.cancel_rounded,
            size: 13,
            color: met ? Colors.green.shade600 : Colors.red.shade500,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.65))),
          ),
        ],
      ),
    );
  }
}

class _PasswordStrength {
  _PasswordStrength(this.label, this.value, this.color, {required this.valid});
  final String label;
  final double value;
  final Color color;
  final bool valid;
}
