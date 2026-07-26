import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_config.dart';
import 'main.dart' show kAuthRedirectUrl;

/// Sign-up screen — mirrors the web `components/auth-dialog.tsx` Sign Up tab.
///
/// Flow:
///   1. Collect email, full name, phone (with country code), password and confirm password.
///   2. Validate password against the same rules as the web (min 11 chars, lower + upper +
///      number + symbol; "strong" at >= 14 chars).
///   3. Call `supabase.auth.signUp`, then upsert into the `users` table with
///      `{ id, email, name, phone: "<code> <number>" }`.
///   4. Pop back to the caller with the email so the login screen can prefill it.
///
/// Returns the created email (as `String`) via `Navigator.pop` on success, or `null` on cancel.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _CountryCode {
  const _CountryCode({required this.code, required this.flag, required this.country});
  final String code;
  final String flag;
  final String country;
}

const List<_CountryCode> _kCountryCodes = [
  _CountryCode(code: '+91', flag: '🇮🇳', country: 'India'),
  _CountryCode(code: '+1', flag: '🇺🇸', country: 'USA'),
  _CountryCode(code: '+44', flag: '🇬🇧', country: 'UK'),
  _CountryCode(code: '+61', flag: '🇦🇺', country: 'Australia'),
  _CountryCode(code: '+971', flag: '🇦🇪', country: 'UAE'),
  _CountryCode(code: '+65', flag: '🇸🇬', country: 'Singapore'),
  _CountryCode(code: '+60', flag: '🇲🇾', country: 'Malaysia'),
  _CountryCode(code: '+94', flag: '🇱🇰', country: 'Sri Lanka'),
  _CountryCode(code: '+49', flag: '🇩🇪', country: 'Germany'),
  _CountryCode(code: '+33', flag: '🇫🇷', country: 'France'),
  _CountryCode(code: '+81', flag: '🇯🇵', country: 'Japan'),
  _CountryCode(code: '+86', flag: '🇨🇳', country: 'China'),
  _CountryCode(code: '+966', flag: '🇸🇦', country: 'Saudi Arabia'),
  _CountryCode(code: '+974', flag: '🇶🇦', country: 'Qatar'),
  _CountryCode(code: '+968', flag: '🇴🇲', country: 'Oman'),
  _CountryCode(code: '+973', flag: '🇧🇭', country: 'Bahrain'),
  _CountryCode(code: '+64', flag: '🇳🇿', country: 'New Zealand'),
  _CountryCode(code: '+27', flag: '🇿🇦', country: 'South Africa'),
];

/// National-number digit cap + hyphen grouping for display (excluding country code).
class _NationalPhoneRules {
  const _NationalPhoneRules({
    required this.maxDigits,
    required this.groupSizes,
    required this.exampleHint,
  });

  /// Subscriber digits only (no country code).
  final int maxDigits;

  /// Hyphen breaks: e.g. [3, 3, 4] → XXX-XXX-XXXX
  final List<int> groupSizes;

  final String exampleHint;
}

_NationalPhoneRules _nationalPhoneRulesForCountry(String countryDialCode) {
  switch (countryDialCode) {
    case '+91':
      return const _NationalPhoneRules(maxDigits: 10, groupSizes: [5, 5], exampleHint: '98765-43210');
    case '+1':
      return const _NationalPhoneRules(maxDigits: 10, groupSizes: [3, 3, 4], exampleHint: '555-123-4567');
    case '+44':
      return const _NationalPhoneRules(maxDigits: 10, groupSizes: [4, 3, 3], exampleHint: '7700-900-123');
    case '+61':
      return const _NationalPhoneRules(maxDigits: 9, groupSizes: [3, 3, 3], exampleHint: '412-345-678');
    case '+971':
      return const _NationalPhoneRules(maxDigits: 9, groupSizes: [3, 3, 3], exampleHint: '501-234-567');
    case '+65':
      return const _NationalPhoneRules(maxDigits: 8, groupSizes: [4, 4], exampleHint: '9123-4567');
    case '+60':
      return const _NationalPhoneRules(maxDigits: 10, groupSizes: [3, 3, 4], exampleHint: '123-456-7890');
    case '+94':
      return const _NationalPhoneRules(maxDigits: 9, groupSizes: [3, 3, 3], exampleHint: '771-234-567');
    case '+49':
      return const _NationalPhoneRules(maxDigits: 11, groupSizes: [4, 4, 3], exampleHint: '1512-3456-789');
    case '+33':
      return const _NationalPhoneRules(maxDigits: 9, groupSizes: [2, 2, 2, 3], exampleHint: '06-12-34-567');
    case '+81':
      return const _NationalPhoneRules(maxDigits: 10, groupSizes: [3, 3, 4], exampleHint: '090-1234-5678');
    case '+86':
      return const _NationalPhoneRules(maxDigits: 11, groupSizes: [3, 4, 4], exampleHint: '138-0013-8000');
    case '+966':
      return const _NationalPhoneRules(maxDigits: 9, groupSizes: [3, 3, 3], exampleHint: '501-234-567');
    case '+974':
      return const _NationalPhoneRules(maxDigits: 8, groupSizes: [4, 4], exampleHint: '3312-3456');
    case '+968':
      return const _NationalPhoneRules(maxDigits: 8, groupSizes: [4, 4], exampleHint: '9123-4567');
    case '+973':
      return const _NationalPhoneRules(maxDigits: 8, groupSizes: [4, 4], exampleHint: '3678-9012');
    case '+64':
      return const _NationalPhoneRules(maxDigits: 9, groupSizes: [3, 3, 3], exampleHint: '021-234-567');
    case '+27':
      return const _NationalPhoneRules(maxDigits: 9, groupSizes: [3, 3, 3], exampleHint: '082-123-456');
    default:
      return const _NationalPhoneRules(maxDigits: 15, groupSizes: [4, 4, 4, 3], exampleHint: '1234-5678-9012');
  }
}

String _formatNationalDigitsWithHyphens(String digits, List<int> groupSizes) {
  if (digits.isEmpty) return '';
  final buf = StringBuffer();
  var pos = 0;
  var gi = 0;
  while (pos < digits.length && gi < groupSizes.length) {
    final chunk = math.min(groupSizes[gi], digits.length - pos);
    if (chunk <= 0) break;
    if (buf.isNotEmpty) buf.write('-');
    buf.write(digits.substring(pos, pos + chunk));
    pos += chunk;
    gi++;
  }
  if (pos < digits.length) {
    if (buf.isNotEmpty) buf.write('-');
    buf.write(digits.substring(pos));
  }
  return buf.toString();
}

/// Keeps only digits, caps at [maxDigits], inserts hyphens per [groupSizes].
class _NationalPhoneInputFormatter extends TextInputFormatter {
  _NationalPhoneInputFormatter({
    required this.maxDigits,
    required this.groupSizes,
  });

  final int maxDigits;
  final List<int> groupSizes;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    final truncated = digits.length > maxDigits ? digits.substring(0, maxDigits) : digits;
    final formatted = _formatNationalDigitsWithHyphens(truncated, groupSizes);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _PasswordStrength {
  const _PasswordStrength({
    required this.label,
    required this.value,
    required this.color,
    required this.isValid,
  });
  final String label;
  final double value; // 0..1
  final Color color;
  final bool isValid;
}

class _SignupScreenState extends State<SignupScreen> {
  static const Color _brand = Color(0xFF2FA086);
  static const Color _fieldFill = Color(0xFFF5F6FA);
  static const Color _errorRed = Color(0xFFDC2626);

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  String _countryCode = '+91';
  bool _showPassword = false;
  bool _showConfirm = false;
  bool _isLoading = false;
  String? _errorMessage;

  /// Which input(s) the current error applies to. Names: 'email', 'name',
  /// 'phone', 'password', 'confirm'. Used to render a red border around
  /// the offending field(s).
  Set<String> _errorFields = const <String>{};

  /// When true, the inline error block also surfaces a "Contact admin" CTA
  /// (used for "email/phone already exists" cases).
  bool _showContactAdmin = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() => setState(() {}));
    _confirmController.addListener(() => setState(() {}));
    _phoneController.addListener(() => setState(() {}));
  }

  void _reformatPhoneAfterCountryChange() {
    final rules = _nationalPhoneRulesForCountry(_countryCode);
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final truncated =
        digits.length > rules.maxDigits ? digits.substring(0, rules.maxDigits) : digits;
    final formatted = _formatNationalDigitsWithHyphens(truncated, rules.groupSizes);
    _phoneController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // -------------------- Password strength (mirrors web) --------------------

  _PasswordStrength _computeStrength(String password) {
    if (password.isEmpty) {
      return const _PasswordStrength(
        label: '',
        value: 0,
        color: Color(0xFFE5E7EB),
        isValid: false,
      );
    }
    final hasMinLength = password.length >= 11;
    final hasLowercase = RegExp(r'[a-z]').hasMatch(password);
    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
    final hasNumber = RegExp(r'\d').hasMatch(password);
    final hasSymbol = RegExp(r'[^A-Za-z0-9]').hasMatch(password);

    final criteriaMet = [
      hasMinLength,
      hasLowercase,
      hasUppercase,
      hasNumber,
      hasSymbol,
    ].where((c) => c).length;

    if (!hasMinLength || criteriaMet < 5) {
      return const _PasswordStrength(
        label: 'Does not meet requirements',
        value: 0.30,
        color: Color(0xFFEF4444),
        isValid: false,
      );
    }
    if (password.length >= 14) {
      return const _PasswordStrength(
        label: 'Strong password',
        value: 1.0,
        color: Color(0xFF10B981),
        isValid: true,
      );
    }
    return const _PasswordStrength(
      label: 'Meets minimum requirements',
      value: 0.70,
      color: Color(0xFFF59E0B),
      isValid: true,
    );
  }

  bool get _passwordsMatch =>
      _confirmController.text.isEmpty ||
      _passwordController.text == _confirmController.text;

  /// Parses JSON-RPC / jsonb payloads from PostgREST (Map, or JSON string).
  Map<String, dynamic>? _parseJsonMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {}
    }
    return null;
  }

  bool _truthy(dynamic v) {
    if (v == true) return true;
    if (v == false || v == null) return false;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == 't' || s == '1' || s == 'yes';
  }

  // -------------------- Submit --------------------

  /// Looks up whether email / national phone digits already exist.
  ///
  /// Prefer `check_signup_availability` RPC (see `manavizha/migrations/signup_availability_check.sql`)
  /// so duplicate detection works even when RLS blocks anonymous `SELECT` on `users`.
  /// Falls back to direct queries only if the RPC is missing / fails.
  Future<String?> _findExistingAccount({
    required String email,
    required String phoneDigitsOnly,
  }) async {
    final client = Supabase.instance.client;

    try {
      final res = await client.rpc(
        'check_signup_availability',
        params: <String, dynamic>{
          'p_email': email,
          'p_phone_digits': phoneDigitsOnly,
        },
      );
      final m = _parseJsonMap(res);
      if (m != null) {
        final emailTaken = _truthy(m['email_taken']);
        final phoneTaken = _truthy(m['phone_taken']);
        if (emailTaken && phoneTaken) return 'both';
        if (emailTaken) return 'email';
        if (phoneTaken) return 'phone';
        return null;
      }
    } catch (_) {
      // RPC not deployed yet, or transient error — try client-side below.
    }

    return _findExistingAccountClientFallback(
      client: client,
      email: email,
      phoneDigitsOnly: phoneDigitsOnly,
    );
  }

  /// Direct table reads — often blocked by RLS for anonymous users; kept as fallback only.
  Future<String?> _findExistingAccountClientFallback({
    required SupabaseClient client,
    required String email,
    required String phoneDigitsOnly,
  }) async {
    bool emailTaken = false;
    bool phoneTaken = false;

    try {
      final emailRow = await client
          .from('users')
          .select('id')
          .ilike('email', email)
          .limit(1)
          .maybeSingle();
      emailTaken = emailRow != null;
    } catch (_) {}

    if (phoneDigitsOnly.isNotEmpty) {
      bool rowMatchesPhone(String? rawPhone) {
        final d = (rawPhone ?? '').replaceAll(RegExp(r'\D'), '');
        if (d.isEmpty || phoneDigitsOnly.isEmpty) return false;
        return d == phoneDigitsOnly ||
            (d.length >= phoneDigitsOnly.length &&
                d.endsWith(phoneDigitsOnly)) ||
            (phoneDigitsOnly.length >= d.length &&
                phoneDigitsOnly.endsWith(d));
      }

      try {
        final userPhones = await client.from('users').select('phone');
        for (final r in (userPhones as List?) ?? const []) {
          if (r is Map && rowMatchesPhone(r['phone']?.toString())) {
            phoneTaken = true;
            break;
          }
        }
      } catch (_) {}

      if (!phoneTaken) {
        try {
          final contactPhones = await client.from('contact_details').select('phone');
          for (final r in (contactPhones as List?) ?? const []) {
            if (r is Map && rowMatchesPhone(r['phone']?.toString())) {
              phoneTaken = true;
              break;
            }
          }
        } catch (_) {}
      }
    }

    if (emailTaken && phoneTaken) return 'both';
    if (emailTaken) return 'email';
    if (phoneTaken) return 'phone';
    return null;
  }

  void _setError(
    String message, {
    Set<String> fields = const <String>{},
    bool contactAdmin = false,
  }) {
    setState(() {
      _errorMessage = message;
      _errorFields = fields;
      _showContactAdmin = contactAdmin;
      _isLoading = false;
    });
  }

  /// Clear field highlighting as soon as the user starts editing the
  /// offending input.
  void _clearErrorFor(String field) {
    if (_errorFields.contains(field)) {
      setState(() {
        _errorFields = _errorFields.where((f) => f != field).toSet();
        if (_errorFields.isEmpty) {
          _errorMessage = null;
          _showContactAdmin = false;
        }
      });
    }
  }

  Future<void> _handleSignup() async {
    setState(() {
      _errorMessage = null;
      _errorFields = const <String>{};
      _showContactAdmin = false;
    });

    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final phoneDigitsOnly = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final phoneRules = _nationalPhoneRulesForCountry(_countryCode);
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    final empties = <String>{};
    if (email.isEmpty) empties.add('email');
    if (name.isEmpty) empties.add('name');
    if (phoneDigitsOnly.isEmpty) empties.add('phone');
    if (password.isEmpty) empties.add('password');
    if (confirm.isEmpty) empties.add('confirm');
    if (empties.isNotEmpty) {
      _setError('Please fill in all the fields above.', fields: empties);
      return;
    }

    if (phoneDigitsOnly.length != phoneRules.maxDigits) {
      _setError(
        'Enter all ${phoneRules.maxDigits} digits of your phone number for this country.',
        fields: const {'phone'},
      );
      return;
    }

    final strength = _computeStrength(password);
    if (!strength.isValid) {
      _setError(
        'Your password does not meet the minimum requirements yet.',
        fields: const {'password'},
      );
      return;
    }
    if (password != confirm) {
      _setError(
        'Passwords do not match. Please re-enter the same password to confirm.',
        fields: const {'confirm'},
      );
      return;
    }

    setState(() => _isLoading = true);

    final existing = await _findExistingAccount(
      email: email,
      phoneDigitsOnly: phoneDigitsOnly,
    );

    if (existing != null) {
      final what = switch (existing) {
        'email' => 'email address',
        'phone' => 'phone number',
        _ => 'email address and phone number',
      };
      final fields = switch (existing) {
        'email' => const {'email'},
        'phone' => const {'phone'},
        _ => const {'email', 'phone'},
      };
      _setError(
        'An account with this $what already exists. If you believe this is a '
        'mistake, please contact the administrator.',
        fields: fields,
        contactAdmin: true,
      );
      return;
    }

    try {
      final client = Supabase.instance.client;
      final auth = await client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: kAuthRedirectUrl,
      );

      final user = auth.user;
      if (user == null) {
        if (!mounted) return;
        _setError('Could not create your account. Please try again.');
        return;
      }

      try {
        await client.from('users').upsert(
          {
            'id': user.id,
            'email': user.email,
            'name': name.isEmpty ? null : name,
            'phone':
                phoneDigitsOnly.isEmpty ? null : '$_countryCode $phoneDigitsOnly',
          },
          onConflict: 'id',
        );
      } on PostgrestException catch (e) {
        if (!mounted) return;
        final msg = e.message.toLowerCase();
        final code = e.code;
        final dupPhone = code == '23505' ||
            msg.contains('phone number is already') ||
            msg.contains('already registered') ||
            (msg.contains('duplicate') && msg.contains('phone'));
        _setError(
          dupPhone
              ? 'An account with this phone number already exists. If you '
                  'believe this is a mistake, please contact the administrator.'
              : e.message,
          fields: dupPhone ? const {'phone'} : const <String>{},
          contactAdmin: dupPhone,
        );
        return;
      }

      if (!mounted) return;
      // "Check your inbox" notice — mirrors the web AuthDialog, which tells
      // the member to confirm their email before the first sign-in.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: const [
              Icon(Icons.mark_email_unread_rounded,
                  color: Color(0xFF2FA086), size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text('Verify your email',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          content: Text(
            'Account created! We\'ve sent a confirmation link to\n\n$email\n\n'
            'Open it to verify your email, then sign in to continue.',
            style: const TextStyle(fontSize: 13.5, height: 1.45),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2FA086)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop<String>(email);
    } on AuthException catch (e) {
      if (!mounted) return;
      // Supabase auth itself enforces email uniqueness — surface that with
      // the same contact-admin affordance so the message lines up with the
      // pre-check above.
      final msg = e.message.toLowerCase();
      final isDuplicate = msg.contains('already') ||
          msg.contains('registered') ||
          msg.contains('exists') ||
          msg.contains('user already');
      _setError(
        isDuplicate
            ? 'An account with this email address already exists. If you '
                'believe this is a mistake, please contact the administrator.'
            : e.message,
        fields: isDuplicate ? const {'email'} : const <String>{},
        contactAdmin: isDuplicate,
      );
    } catch (_) {
      if (!mounted) return;
      _setError('An unexpected error occurred. Please try again.');
    }
  }

  // -------------------- Contact admin actions --------------------

  Future<void> _emailAdmin() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConfig.adminEmail,
      queryParameters: {
        'subject': 'Sign up issue – existing account',
        'body':
            'Hi,\n\nI tried to sign up for Manavizha but the app says an '
            'account with my email or phone number already exists. Could you '
            'please help me recover or update my account?\n\n'
            'My details:\n'
            'Name: ${_nameController.text.trim()}\n'
            'Email: ${_emailController.text.trim()}\n'
            'Phone: $_countryCode ${_phoneController.text.replaceAll(RegExp(r'\D'), '')}\n',
      },
    );
    await _safeLaunch(uri);
  }

  Future<void> _callAdmin() async {
    final tel = AppConfig.adminPhone.replaceAll(' ', '');
    await _safeLaunch(Uri(scheme: 'tel', path: tel));
  }

  Future<void> _safeLaunch(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open ${uri.scheme} app.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.scheme} app: $e')),
      );
    }
  }

  // -------------------- Build --------------------

  @override
  Widget build(BuildContext context) {
    final strength = _computeStrength(_passwordController.text);
    final phoneRules = _nationalPhoneRulesForCountry(_countryCode);
    final phoneDigitsEntered =
        _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final phoneComplete = phoneDigitsEntered.length == phoneRules.maxDigits;
    final canSubmit =
        !_isLoading && strength.isValid && _passwordsMatch && phoneComplete;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              const Text(
                'Create an account',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E1E1E),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Join the community and start connecting with verified members.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black54,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 32),

              _label('Email Address'),
              const SizedBox(height: 8),
              _textField(
                controller: _emailController,
                hint: 'you@email.com',
                keyboardType: TextInputType.emailAddress,
                prefix: const Icon(Icons.email_outlined, color: Colors.black45),
                autofillHints: const [AutofillHints.email],
                hasError: _errorFields.contains('email'),
                onChanged: (_) => _clearErrorFor('email'),
              ),
              const SizedBox(height: 20),

              _label('Full Name'),
              const SizedBox(height: 8),
              _textField(
                controller: _nameController,
                hint: 'Your full name',
                keyboardType: TextInputType.name,
                prefix: const Icon(Icons.person_outline, color: Colors.black45),
                autofillHints: const [AutofillHints.name],
                hasError: _errorFields.contains('name'),
                onChanged: (_) => _clearErrorFor('name'),
              ),
              const SizedBox(height: 20),

              _label('Phone Number'),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _fieldFill,
                          borderRadius: BorderRadius.circular(12),
                          border: _errorFields.contains('phone')
                              ? Border.all(color: _errorRed, width: 1.5)
                              : null,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _countryCode,
                            isDense: true,
                            borderRadius: BorderRadius.circular(12),
                            items: _kCountryCodes
                                .map(
                                  (c) => DropdownMenuItem<String>(
                                    value: c.code,
                                    child: Text(
                                      '${c.flag} ${c.code}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _countryCode = v;
                                  _reformatPhoneAfterCountryChange();
                                });
                                _clearErrorFor('phone');
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _textField(
                          controller: _phoneController,
                          hint: phoneRules.exampleHint,
                          keyboardType: TextInputType.phone,
                          prefix:
                              const Icon(Icons.phone_outlined, color: Colors.black45),
                          inputFormatters: [
                            _NationalPhoneInputFormatter(
                              maxDigits: phoneRules.maxDigits,
                              groupSizes: phoneRules.groupSizes,
                            ),
                          ],
                          autofillHints: const [AutofillHints.telephoneNumberNational],
                          hasError: _errorFields.contains('phone'),
                          onChanged: (_) => _clearErrorFor('phone'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${phoneDigitsEntered.length}/${phoneRules.maxDigits} digits',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: phoneComplete
                          ? const Color(0xFF059669)
                          : Colors.black45,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              _label('Password'),
              const SizedBox(height: 8),
              _textField(
                controller: _passwordController,
                hint: '••••••••',
                obscure: !_showPassword,
                prefix: const Icon(Icons.lock_outline, color: Colors.black45),
                suffix: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility : Icons.visibility_off,
                    color: Colors.black45,
                  ),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
                autofillHints: const [AutofillHints.newPassword],
                hasError: _errorFields.contains('password'),
                onChanged: (_) => _clearErrorFor('password'),
              ),
              if (_passwordController.text.isNotEmpty) ...[
                const SizedBox(height: 12),
                _passwordChecklist(strength),
              ],
              const SizedBox(height: 20),

              _label('Confirm Password'),
              const SizedBox(height: 8),
              _textField(
                controller: _confirmController,
                hint: 'Repeat password',
                obscure: !_showConfirm,
                prefix: const Icon(Icons.lock_outline, color: Colors.black45),
                suffix: IconButton(
                  icon: Icon(
                    _showConfirm ? Icons.visibility : Icons.visibility_off,
                    color: Colors.black45,
                  ),
                  onPressed: () => setState(() => _showConfirm = !_showConfirm),
                ),
                autofillHints: const [AutofillHints.newPassword],
                hasError: _errorFields.contains('confirm'),
                onChanged: (_) => _clearErrorFor('confirm'),
              ),
              if (_confirmController.text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _passwordsMatch
                          ? Icons.check_circle
                          : Icons.cancel,
                      size: 16,
                      color: _passwordsMatch
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _passwordsMatch ? 'Passwords match' : 'Passwords do not match',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _passwordsMatch
                            ? const Color(0xFF059669)
                            : const Color(0xFFDC2626),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),

              if (_errorMessage != null) _buildErrorBlock(),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: canSubmit ? _handleSignup : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                    shadowColor: _brand.withValues(alpha: 0.4),
                    disabledBackgroundColor: _brand.withValues(alpha: 0.4),
                    disabledForegroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Create Account',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Already have an account?',
                    style: TextStyle(color: Colors.black54),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Log In',
                      style: TextStyle(
                        color: _brand,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'By continuing, you agree to our Terms of Service and Privacy Policy.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black45,
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------- Reusable bits --------------------

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1E1E1E),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? prefix,
    Widget? suffix,
    List<TextInputFormatter>? inputFormatters,
    Iterable<String>? autofillHints,
    bool hasError = false,
    ValueChanged<String>? onChanged,
  }) {
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _errorRed, width: 1.5),
    );
    final defaultBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: hasError ? _errorRed : _brand,
        width: 1.5,
      ),
    );

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      inputFormatters: inputFormatters,
      autofillHints: autofillHints,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.black38),
        prefixIcon: prefix,
        suffixIcon: suffix,
        filled: true,
        fillColor: _fieldFill,
        border: hasError ? errorBorder : defaultBorder,
        enabledBorder: hasError ? errorBorder : defaultBorder,
        focusedBorder: focusedBorder,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
    );
  }

  Widget _buildErrorBlock() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        border: Border.all(color: const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline,
                  color: _errorRed, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          if (_showContactAdmin) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFFECACA)),
            const SizedBox(height: 10),
            const Text(
              'Contact administrator',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Color(0xFF7F1D1D),
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: _emailAdmin,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.email_outlined,
                        size: 16, color: Color(0xFFB91C1C)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppConfig.adminEmail,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB91C1C),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const Icon(Icons.open_in_new,
                        size: 14, color: Color(0xFFB91C1C)),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: _callAdmin,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.phone_outlined,
                        size: 16, color: Color(0xFFB91C1C)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppConfig.adminPhone,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB91C1C),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const Icon(Icons.open_in_new,
                        size: 14, color: Color(0xFFB91C1C)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _passwordChecklist(_PasswordStrength strength) {
    final pwd = _passwordController.text;
    final hasMin = pwd.length >= 11;
    final hasMixedCase = RegExp(r'[a-z]').hasMatch(pwd) && RegExp(r'[A-Z]').hasMatch(pwd);
    final hasNumber = RegExp(r'\d').hasMatch(pwd);
    final hasSymbol = RegExp(r'[^A-Za-z0-9]').hasMatch(pwd);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Password strength',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              Text(
                strength.label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: strength.value,
              minHeight: 5,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: AlwaysStoppedAnimation<Color>(strength.color),
            ),
          ),
          const SizedBox(height: 10),
          _criteriaRow('Minimum 11 characters', hasMin),
          _criteriaRow('Lowercase & uppercase letters', hasMixedCase),
          _criteriaRow('At least one number', hasNumber),
          _criteriaRow('At least one symbol', hasSymbol),
        ],
      ),
    );
  }

  Widget _criteriaRow(String text, bool ok) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel,
            size: 14,
            color: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: ok ? const Color(0xFF065F46) : const Color(0xFF991B1B),
            ),
          ),
        ],
      ),
    );
  }
}
