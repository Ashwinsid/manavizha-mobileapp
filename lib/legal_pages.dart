import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_home_screen.dart';
import 'app_config.dart';

/// Flutter ports of `manavizha/app/privacy-policy/page.tsx` and
/// `manavizha/app/terms-of-service/page.tsx`. Plain text content so the
/// partner-area Settings tab no longer has to bounce users to the website.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const Color _brand = AdminHomeScreen.brandPurple;

  static final List<_LegalSection> _sections = [
    _LegalSection(
      title: '1. Introduction',
      paragraphs: [
        'Welcome to Manavizha. We are committed to protecting your privacy and ensuring the security of your personal information. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our matrimonial services platform.',
      ],
    ),
    _LegalSection(
      title: '2. Information we collect',
      paragraphs: [
        'Personal information you provide directly, including:',
      ],
      bullets: [
        'Name, date of birth, and gender',
        'Contact details (email, phone number, address)',
        'Educational and professional details',
        'Family background information',
        'Photographs and profile information',
        'Preferences and interests',
      ],
      followUp: [
        'We also automatically collect device information, IP address, browser type, pages visited, and interactions to improve the service.',
      ],
    ),
    _LegalSection(
      title: '3. How we use your information',
      paragraphs: ['We use the information we collect to:'],
      bullets: [
        'Provide and improve our matrimonial services',
        'Match you with potential partners based on your preferences',
        'Communicate with you about your account and our services',
        'Send notifications and updates',
        'Verify your identity and prevent fraud',
        'Analyze usage patterns to enhance the user experience',
        'Comply with legal obligations',
      ],
    ),
    _LegalSection(
      title: '4. Information sharing and disclosure',
      paragraphs: [
        'We do not sell your personal information. We may share it only with:',
      ],
      bullets: [
        'Other registered users as part of our matching services',
        'Service providers who assist us in operating the platform',
        'Authorities when required by law or to protect our rights',
        'A successor entity in case of a merger or business transfer',
        'Anyone you give explicit consent to share with',
      ],
    ),
    _LegalSection(
      title: '5. Data security',
      paragraphs: [
        'We implement appropriate technical and organizational measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction. However, no method of transmission over the internet is 100% secure, and we cannot guarantee absolute security.',
      ],
    ),
    _LegalSection(
      title: '6. Your rights',
      paragraphs: ['You have the right to:'],
      bullets: [
        'Access and review your personal information',
        'Update or correct inaccurate information',
        'Request deletion of your account and data',
        'Opt-out of non-essential communications',
        'Object to processing of your personal information',
        'Data portability',
      ],
    ),
    _LegalSection(
      title: "7. Children's privacy",
      paragraphs: [
        'Our services are intended for individuals 18 years of age or older. We do not knowingly collect information from children under 18 and will delete any such information promptly when discovered.',
      ],
    ),
    _LegalSection(
      title: '8. Changes to this policy',
      paragraphs: [
        'We may update this Privacy Policy from time to time. We will notify you of changes by posting the updated text in the app and updating the "last updated" date. Please review this policy periodically.',
      ],
    ),
    _LegalSection(
      title: '9. Contact us',
      paragraphs: [
        'For any questions about this Privacy Policy or our practices, contact the Manavizha team via the Contact admin entry in the Settings screen.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _LegalScaffold(
      title: 'Privacy policy',
      accent: _brand,
      sections: _sections,
    );
  }
}

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const Color _brand = AdminHomeScreen.brandPurple;

  static final List<_LegalSection> _sections = [
    _LegalSection(
      title: '1. Acceptance of terms',
      paragraphs: [
        'By accessing and using Manavizha you agree to be bound by these Terms of Service. If you do not agree, please do not use the platform.',
      ],
    ),
    _LegalSection(
      title: '2. Eligibility',
      paragraphs: ['To use our services you must:'],
      bullets: [
        'Be at least 18 years of age',
        'Be legally eligible to marry under the laws of your jurisdiction',
        'Provide accurate, current, and complete information',
        'Maintain the security of your account credentials',
        'Not have been previously removed from the platform',
      ],
    ),
    _LegalSection(
      title: '3. User accounts',
      paragraphs: [
        'You are responsible for the activity on your account. You agree to provide truthful information, keep it updated, notify us immediately of unauthorized use, and accept responsibility for activity performed under your account.',
      ],
    ),
    _LegalSection(
      title: '4. User conduct',
      paragraphs: ['You agree NOT to:'],
      bullets: [
        'Post false, misleading, or fraudulent information',
        'Harass, abuse, or harm other users',
        'Use the platform for any illegal purpose',
        'Impersonate any person or entity',
        'Upload viruses or malicious code',
        'Spam or send unsolicited communications',
        "Interfere with the platform's operation",
      ],
    ),
    _LegalSection(
      title: '5. Content and intellectual property',
      paragraphs: [
        'All content on the platform — text, graphics, logos, software — is the property of Manavizha or its suppliers and is protected by copyright and other intellectual property laws. You may not reproduce, distribute, or create derivative works without permission.',
      ],
    ),
    _LegalSection(
      title: '6. User-generated content',
      paragraphs: [
        'You retain ownership of content you post on the platform. By posting, you grant us a worldwide, non-exclusive, royalty-free license to use, reproduce, and distribute your content for the purpose of operating and promoting the service.',
      ],
    ),
    _LegalSection(
      title: '7. Prohibited activities',
      paragraphs: ['The following are strictly prohibited:'],
      bullets: [
        'Creating fake profiles or impersonating others',
        'Engaging in fraudulent or deceptive practices',
        'Soliciting money or financial assistance',
        'Sharing contact information before appropriate verification',
        'Reverse-engineering or scraping the platform',
      ],
    ),
    _LegalSection(
      title: '8. Termination',
      paragraphs: [
        'We may suspend or terminate your account at any time for violations of these Terms or for behaviour that risks the integrity or safety of the platform.',
      ],
    ),
    _LegalSection(
      title: '9. Limitation of liability',
      paragraphs: [
        'Manavizha is provided on an "as is" basis. To the extent permitted by law, we disclaim all warranties and limit our liability for any indirect, incidental, or consequential damages arising from your use of the service.',
      ],
    ),
    _LegalSection(
      title: '10. Changes to these terms',
      paragraphs: [
        'We may update these Terms of Service from time to time. Continued use of the platform after changes are posted constitutes acceptance of the new Terms.',
      ],
    ),
    _LegalSection(
      title: '11. Contact us',
      paragraphs: [
        'For questions about these Terms of Service, contact the Manavizha team via the Contact admin entry in the Settings screen.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _LegalScaffold(
      title: 'Terms of service',
      accent: _brand,
      sections: _sections,
    );
  }
}

/// Port of `manavizha/app/contact/page.tsx` — public Contact Us page with
/// the same three contact cards (email · phone · location), business
/// hours, and a "Send us a Message" form. The web form is a setTimeout
/// mock; on Flutter we hand off to the user's default mail client via
/// `mailto:` with a pre-filled body so the message actually delivers.
class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  static const Color _brand = AdminHomeScreen.brandPurple;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _submitting = false;
  String? _statusMessage;
  bool _statusSuccess = false;
  Timer? _statusTimer;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _subject.dispose();
    _message.dispose();
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _launchUri(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.scheme}: link')),
      );
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _statusMessage = null;
    });
    try {
      final to = AppConfig.adminEmail;
      final subject = _subject.text.trim().isEmpty
          ? 'Manavizha contact: enquiry'
          : 'Manavizha contact: ${_subject.text.trim()}';
      final bodyLines = <String>[
        'Name: ${_name.text.trim()}',
        if (_email.text.trim().isNotEmpty) 'Email: ${_email.text.trim()}',
        if (_phone.text.trim().isNotEmpty) 'Phone: ${_phone.text.trim()}',
        '',
        _message.text.trim(),
      ];
      // `mailto:` parameters must be application/x-www-form-urlencoded,
      // which is what `Uri(queryParameters: ...)` produces by default.
      final mail = Uri(
        scheme: 'mailto',
        path: to,
        queryParameters: {
          'subject': subject,
          'body': bodyLines.join('\n'),
        },
      );
      await _launchUri(mail);
      if (!mounted) return;
      setState(() {
        _statusSuccess = true;
        _statusMessage =
            'Thanks! Your mail client should now be open with the message ready to send.';
      });
      _name.clear();
      _email.clear();
      _phone.clear();
      _subject.clear();
      _message.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusSuccess = false;
        _statusMessage = 'Something went wrong. Please try again later.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
      _statusTimer?.cancel();
      _statusTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _statusMessage = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: const Text('Contact us'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text(
            'Contact Us',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.4),
          ),
          const SizedBox(height: 8),
          Text(
            "We'd love to hear from you. Get in touch with us using the form below "
            'or contact information provided.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.black.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          _contactCard(),
          const SizedBox(height: 16),
          _businessHoursCard(),
          const SizedBox(height: 16),
          _messageForm(),
        ],
      ),
    );
  }

  Widget _contactCard() {
    return _section(
      title: 'Get in Touch',
      child: Column(
        children: [
          _contactRow(
            icon: Icons.mail_outline_rounded,
            label: 'Email',
            value: AppConfig.adminEmail,
            onTap: () => _launchUri(Uri(scheme: 'mailto', path: AppConfig.adminEmail)),
          ),
          const SizedBox(height: 14),
          _contactRow(
            icon: Icons.call_rounded,
            label: 'Phone',
            value: AppConfig.adminPhone,
            onTap: () => _launchUri(Uri(
              scheme: 'tel',
              path: AppConfig.adminPhone.replaceAll(' ', ''),
            )),
          ),
          const SizedBox(height: 14),
          _contactRow(
            icon: Icons.place_rounded,
            label: 'Location',
            value: 'India',
          ),
        ],
      ),
    );
  }

  Widget _businessHoursCard() {
    return _section(
      title: 'Business Hours',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _HoursRow(label: 'Monday – Friday', value: '9:00 AM – 6:00 PM'),
          SizedBox(height: 6),
          _HoursRow(label: 'Saturday', value: '10:00 AM – 4:00 PM'),
          SizedBox(height: 6),
          _HoursRow(label: 'Sunday', value: 'Closed'),
        ],
      ),
    );
  }

  Widget _messageForm() {
    return _section(
      title: 'Send us a Message',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field(
              controller: _name,
              label: 'Name *',
              hint: 'Your name',
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter your name'
                  : null,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _email,
              label: 'Email *',
              hint: 'your.email@example.com',
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Please enter your email';
                final ok = RegExp(r'^[\w.\-+]+@[\w\-]+(\.[\w\-]+)+$').hasMatch(t);
                return ok ? null : 'Please enter a valid email address';
              },
            ),
            const SizedBox(height: 12),
            _field(
              controller: _phone,
              label: 'Phone',
              hint: '+91 1234567890',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _subject,
              label: 'Subject *',
              hint: 'What is this regarding?',
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter a subject'
                  : null,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _message,
              label: 'Message *',
              hint: 'Tell us how we can help…',
              minLines: 5,
              maxLines: 8,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter a message'
                  : null,
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusSuccess
                      ? const Color(0xFFE6F8EE)
                      : const Color(0xFFFDECEC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _statusSuccess
                        ? const Color(0xFFB7E7C9)
                        : const Color(0xFFF5C2C2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _statusSuccess
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      color: _statusSuccess
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFB91C1C),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          color: _statusSuccess
                              ? const Color(0xFF166534)
                              : const Color(0xFF991B1B),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  _submitting ? 'Sending…' : 'Send Message',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: _brand.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
              color: Color(0xFF1E1E1E),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _contactRow({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final inner = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _brand.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _brand, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E1E1E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  color: onTap != null ? _brand : Colors.black.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w600,
                  decoration: onTap != null ? TextDecoration.underline : null,
                  decorationColor: _brand.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (onTap == null) return inner;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: inner),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    int minLines = 1,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFFAFAFD),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _brand, width: 1.4),
        ),
      ),
    );
  }
}

class _HoursRow extends StatelessWidget {
  const _HoursRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E1E1E),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            color: Colors.black.withValues(alpha: 0.62),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LegalScaffold extends StatelessWidget {
  const _LegalScaffold({
    required this.title,
    required this.accent,
    required this.sections,
  });

  final String title;
  final Color accent;
  final List<_LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.4),
          ),
          const SizedBox(height: 6),
          Text(
            'Last updated: ${_formatToday()}',
            style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.5), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          for (final s in sections) ...[
            Text(
              s.title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: accent),
            ),
            const SizedBox(height: 8),
            for (final p in s.paragraphs) ...[
              Text(p, style: const TextStyle(fontSize: 14, height: 1.5)),
              const SizedBox(height: 8),
            ],
            if (s.bullets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final b in s.bullets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 6, right: 8),
                              child: Icon(Icons.fiber_manual_record, size: 6),
                            ),
                            Expanded(
                              child: Text(
                                b,
                                style: const TextStyle(fontSize: 14, height: 1.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            for (final p in s.followUp) ...[
              const SizedBox(height: 8),
              Text(p, style: const TextStyle(fontSize: 14, height: 1.5)),
            ],
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  static String _formatToday() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final now = DateTime.now();
    return '${now.day} ${months[now.month - 1]} ${now.year}';
  }
}

class _LegalSection {
  _LegalSection({
    required this.title,
    required this.paragraphs,
    this.bullets = const [],
    this.followUp = const [],
  });

  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
  final List<String> followUp;
}
