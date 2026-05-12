import 'package:flutter/material.dart';

import 'admin_home_screen.dart';

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
