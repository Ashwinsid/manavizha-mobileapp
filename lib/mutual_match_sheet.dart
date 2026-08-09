import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_home_screen.dart';
import 'web_api.dart';

/// Modal bottom sheet shown for **mutual** matches (both users liked each
/// other). Mirrors the "Mutual Interest" sections inside
/// `manavizha/components/browse-profiles.tsx` (lines ~2027-2160) which surface
/// the full contact, education, profession and family details that are
/// otherwise hidden from regular browse cards.
///
/// Reads (all RLS-tolerant):
///   • `contact_details`         — phone, whatsapp, current/permanent address
///   • `education_details`       — list of qualifications
///   • `profession_employee`     — current employment
///   • `profession_business`     — business profile
///   • `profession_student`      — student profile
///   • `family_details`          — parents, siblings, caste/kulam/gotram
Future<void> showMutualMatchSheet(
  BuildContext context, {
  required String targetUserId,
  required String targetName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => _MutualMatchSheet(
      targetUserId: targetUserId,
      targetName: targetName,
    ),
  );
}

/// Loader result for [_MutualMatchSheet]. Each field is `null` if the row
/// doesn't exist or RLS blocked the read.
@immutable
class _MutualExtras {
  const _MutualExtras({
    this.contact,
    this.contactAllowed = false,
    this.contactError,
    this.contactRemaining,
    this.contactLimit,
    this.education = const [],
    this.employee,
    this.business,
    this.student,
    this.family,
  });

  final Map<String, dynamic>? contact;

  /// True only when POST /api/contact-view approved the unlock (tier limit
  /// enforced server-side, `contact_viewed` notification fired there too).
  final bool contactAllowed;

  /// Server's denial reason (upgrade prompt / limit reached), if any.
  final String? contactError;

  /// Remaining contact views for this session (null = unlimited or unknown).
  final int? contactRemaining;

  /// Total contact view limit for this plan (null = unlimited or unknown).
  final int? contactLimit;

  final List<Map<String, dynamic>> education;
  final Map<String, dynamic>? employee;
  final Map<String, dynamic>? business;
  final Map<String, dynamic>? student;
  final Map<String, dynamic>? family;
}

Future<_MutualExtras> _loadMutualExtras(
  SupabaseClient client,
  String userId,
) async {
  Future<Map<String, dynamic>?> single(String table) async {
    try {
      final r = await client.from(table).select().eq('user_id', userId).maybeSingle();
      if (r == null) return null;
      return Map<String, dynamic>.from(r);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> many(String table) async {
    try {
      final r = await client.from(table).select().eq('user_id', userId);
      return (r as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // Contact details are gated by the web's /api/contact-view — it enforces
  // the per-plan unlock limit, logs the view and notifies the profile owner.
  // Only fetch the contact row once the server approves.
  final unlock = WebApi.post('/api/contact-view', {'viewedUserId': userId});

  final results = await Future.wait<dynamic>([
    many('education_details'),
    single('profession_employee'),
    single('profession_business'),
    single('profession_student'),
    single('family_details'),
  ]);

  final unlockRes = await unlock;
  final allowed = unlockRes.ok && unlockRes.data['allowed'] == true;
  final contact = allowed ? await single('contact_details') : null;

  // Parse remaining / limit from the API response
  // JSON numbers may arrive as int or double — use num to safely convert.
  int? remaining;
  int? limit;
  if (unlockRes.ok) {
    final r = unlockRes.data['remaining'];
    final l = unlockRes.data['limit'];
    if (r != null) remaining = (r as num).toInt();
    if (l != null) limit = (l as num).toInt();
  }

  return _MutualExtras(
    contact: contact,
    contactAllowed: allowed,
    contactError: allowed ? null : unlockRes.error,
    contactRemaining: remaining,
    contactLimit: limit,
    education: results[0] as List<Map<String, dynamic>>,
    employee: results[1] as Map<String, dynamic>?,
    business: results[2] as Map<String, dynamic>?,
    student: results[3] as Map<String, dynamic>?,
    family: results[4] as Map<String, dynamic>?,
  );
}

class _MutualMatchSheet extends StatefulWidget {
  const _MutualMatchSheet({
    required this.targetUserId,
    required this.targetName,
  });

  final String targetUserId;
  final String targetName;

  @override
  State<_MutualMatchSheet> createState() => _MutualMatchSheetState();
}

class _MutualMatchSheetState extends State<_MutualMatchSheet> {
  static const Color _brand = AdminHomeScreen.brandPurple;

  bool _loading = true;
  _MutualExtras _extras = const _MutualExtras();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final res = await _loadMutualExtras(client, widget.targetUserId);
    if (!mounted) return;
    setState(() {
      _extras = res;
      _loading = false;
    });
  }

  Future<void> _openUri(Uri uri, {String? errorLabel}) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorLabel ?? 'Could not open $uri')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorLabel ?? 'Could not open $uri')),
      );
    }
  }

  Future<void> _copyToClipboard(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF8F9FE),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _grabber(),
              _header(),
              if (_loading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: _brand),
                  ),
                )
              else
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + media.padding.bottom),
                    children: _buildSections(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Header / grabber ────────────────────────────────────────────────────

  Widget _grabber() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFFCD34D)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_rounded, size: 12, color: Color(0xFFD97706)),
                SizedBox(width: 4),
                Text(
                  'MUTUAL INTEREST',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Connect with ${widget.targetName}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Full contact, education, profession and family details are unlocked because you both expressed interest.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.4,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
          if (!_loading &&
              _extras.contactAllowed &&
              _extras.contactRemaining != null &&
              _extras.contactLimit != null) ...
            [
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _extras.contactRemaining! <= 3
                      ? const Color(0xFFFEE2E2)
                      : const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.contacts_rounded,
                      size: 12,
                      color: _extras.contactRemaining! <= 3
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF059669),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${_extras.contactRemaining} of ${_extras.contactLimit} contact views remaining',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _extras.contactRemaining! <= 3
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  // ── Section composition ─────────────────────────────────────────────────

  List<Widget> _buildSections() {
    final sections = <Widget>[];

    final contactSection = _contactSection();
    if (contactSection != null) sections.add(contactSection);

    final eduSection = _educationSection();
    if (eduSection != null) sections.add(eduSection);

    final profSection = _professionSection();
    if (profSection != null) sections.add(profSection);

    final famSection = _familySection();
    if (famSection != null) sections.add(famSection);

    if (sections.isEmpty) {
      sections.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 36),
          child: Column(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Colors.black.withValues(alpha: 0.35), size: 48),
              const SizedBox(height: 10),
              Text(
                '${widget.targetName} hasn\'t filled in any contact, education or family details yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return sections.map((s) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: s,
    )).toList();
  }

  Widget _sectionShell({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Color background,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // ── Contact section ─────────────────────────────────────────────────────

  Widget? _contactSection() {
    if (!_extras.contactAllowed) return _lockedContactSection();
    final c = _extras.contact;
    if (c == null) return null;
    final phone = _trim(c['phone']);
    final whatsapp = _trim(c['whatsapp_number']);

    final hasCurrentAddr = _hasAnyAddress(c, 'current_');
    final hasPermanentAddr = _hasAnyAddress(c, 'permanent_');
    if (phone == null &&
        whatsapp == null &&
        !hasCurrentAddr &&
        !hasPermanentAddr) {
      return null;
    }

    return _sectionShell(
      icon: Icons.phone_in_talk_rounded,
      iconColor: _brand,
      background: _brand.withValues(alpha: 0.10),
      title: 'Contact details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (phone != null)
            _contactTile(
              icon: Icons.call_rounded,
              label: 'Phone',
              value: phone,
              tint: _brand,
              onTap: () => _openUri(
                Uri(scheme: 'tel', path: phone),
                errorLabel: 'No phone app available',
              ),
              onLongPress: () => _copyToClipboard(phone, 'Phone'),
            ),
          if (whatsapp != null) ...[
            if (phone != null) const SizedBox(height: 10),
            _contactTile(
              icon: Icons.chat_rounded,
              label: 'WhatsApp',
              value: whatsapp,
              tint: const Color(0xFF16A34A),
              onTap: () {
                final digits = whatsapp.replaceAll(RegExp(r'\D'), '');
                if (digits.isEmpty) return;
                _openUri(
                  Uri.parse('https://wa.me/$digits'),
                  errorLabel: 'Could not open WhatsApp',
                );
              },
              onLongPress: () => _copyToClipboard(whatsapp, 'WhatsApp number'),
            ),
          ],
        ],
      ),
    );
  }

  /// Shown when /api/contact-view denied the unlock — free tier, limit
  /// reached, or a block between the two members. Mirrors the web's locked
  /// contact fields in `profile-detail-view.tsx`.
  Widget _lockedContactSection() {
    return _sectionShell(
      icon: Icons.lock_rounded,
      iconColor: const Color(0xFFB45309),
      background: const Color(0xFFFEF3C7),
      title: 'Contact details',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Text(
          _extras.contactError ??
              'Upgrade to a premium plan to view contact details.',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            height: 1.4,
            color: Color(0xFF92400E),
          ),
        ),
      ),
    );
  }

  Widget _contactTile({
    required IconData icon,
    required String label,
    required String value,
    required Color tint,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    return Material(
      color: tint.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: tint),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w800,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: tint,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded,
                  size: 16, color: tint.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasAnyAddress(Map<String, dynamic> c, String prefix) {
    const keys = [
      'address_line1', 'address_line2', 'landmark', 'area', 'taluk',
      'district', 'division', 'region', 'state', 'country', 'pincode',
    ];
    return keys.any((k) => _trim(c['$prefix$k']) != null);
  }

  Widget _addressBlock(Map<String, dynamic> c, String prefix, String title) {
    final rows = <(String, String)>[
      _row('Address line 1', c['${prefix}address_line1']),
      _row('Address line 2', c['${prefix}address_line2']),
      _row('Landmark', c['${prefix}landmark']),
      _row('Area', c['${prefix}area']),
      _row('Taluk', c['${prefix}taluk']),
      _row('District', c['${prefix}district']),
      _row('Division', c['${prefix}division']),
      _row('Region', c['${prefix}region']),
      _row('State', c['${prefix}state']),
      _row('Country', c['${prefix}country']),
      _row('Pincode', c['${prefix}pincode']),
    ].where((r) => r.$2.isNotEmpty).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
        ),
        _detailRowsGrid(rows),
      ],
    );
  }

  // ── Education section ───────────────────────────────────────────────────

  Widget? _educationSection() {
    if (_extras.education.isEmpty) return null;

    final cards = <Widget>[];
    for (final edu in _extras.education) {
      final level = _eduLabel(edu['education'], edu['education_other']);
      final degree = _eduLabel(edu['degree'], edu['degree_other']);
      final rows = <(String, String)>[
        _row('Level', level),
        _row('Degree', degree),
        _row('Branch', edu['branch']),
        _row('Institution', edu['institution']),
        _row('Graduation year', edu['year_of_graduation']),
        _row('Status', edu['status']),
      ].where((r) => r.$2.isNotEmpty).toList();
      if (rows.isEmpty) continue;
      cards.add(
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: _detailRowsGrid(rows),
        ),
      );
    }
    if (cards.isEmpty) return null;

    return _sectionShell(
      icon: Icons.school_rounded,
      iconColor: const Color(0xFF2563EB),
      background: const Color(0xFFDBEAFE),
      title: 'Educational details',
      child: Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            cards[i],
          ],
        ],
      ),
    );
  }

  String? _eduLabel(dynamic primary, dynamic other) {
    final p = _trim(primary);
    if (p == null) return null;
    if (p == 'Other') {
      final o = _trim(other);
      return o ?? p;
    }
    return p;
  }

  // ── Profession section ──────────────────────────────────────────────────

  Widget? _professionSection() {
    final groups = <(String, List<(String, String)>)>[];

    final emp = _extras.employee;
    if (emp != null) {
      final rows = <(String, String)>[
        _row('Type', 'Employee'),
        _row('Company', emp['company']),
        _row('Designation', emp['designation']),
        _row('Salary', emp['salary']),
        _row('Work location', emp['work_location']),
      ].where((r) => r.$2.isNotEmpty).toList();
      if (rows.length > 1) groups.add(('Employee', rows));
    }
    final bus = _extras.business;
    if (bus != null) {
      final rows = <(String, String)>[
        _row('Type', 'Business'),
        _row('Business', bus['business_name']),
        _row('Designation', bus['designation']),
        _row('Annual returns', bus['annual_returns']),
      ].where((r) => r.$2.isNotEmpty).toList();
      if (rows.length > 1) groups.add(('Business', rows));
    }
    final stu = _extras.student;
    if (stu != null) {
      final rows = <(String, String)>[
        _row('Type', 'Student'),
        _row('Institution', stu['institution']),
        _row('Course', stu['course']),
      ].where((r) => r.$2.isNotEmpty).toList();
      if (rows.length > 1) groups.add(('Student', rows));
    }
    if (groups.isEmpty) return null;

    return _sectionShell(
      icon: Icons.work_rounded,
      iconColor: const Color(0xFF4F46E5),
      background: const Color(0xFFE0E7FF),
      title: 'Professional details',
      child: Column(
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: _detailRowsGrid(groups[i].$2),
            ),
          ],
        ],
      ),
    );
  }

  // ── Family section ──────────────────────────────────────────────────────

  Widget? _familySection() {
    final f = _extras.family;
    if (f == null) return null;
    final rows = <(String, String)>[
      _row("Father's name", f['father_name']),
      _row("Father's occupation", f['father_occupation']),
      _row("Mother's name", f['mother_name']),
      _row("Mother's occupation", f['mother_occupation']),
      _row('Siblings', f['siblings']),
      _row('Caste', f['caste']),
      _row('Subcaste', f['subcaste']),
      _row('Kulam', f['kulam']),
      _row('Gotram', f['gotram']),
      _row('Family type', f['family_type']),
      _row('Family status', f['family_status']),
    ].where((r) => r.$2.isNotEmpty).toList();
    if (rows.isEmpty) return null;

    return _sectionShell(
      icon: Icons.diversity_3_rounded,
      iconColor: const Color(0xFFE11D48),
      background: const Color(0xFFFCE7F3),
      title: 'Family details',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFECDD3)),
        ),
        child: _detailRowsGrid(rows),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Widget _detailRowsGrid(List<(String, String)> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two-column grid above 360 px (matches the web's `grid-cols-2`),
        // single column on small screens.
        final twoCol = constraints.maxWidth >= 360;
        final items = <Widget>[];
        for (final r in rows) {
          items.add(_detailItem(r.$1, r.$2));
        }
        if (!twoCol) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                items[i],
              ],
            ],
          );
        }
        return Wrap(
          spacing: 16,
          runSpacing: 12,
          children: items
              .map((w) => SizedBox(
                    width: (constraints.maxWidth - 16) / 2,
                    child: w,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _detailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.black.withValues(alpha: 0.5),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  String? _trim(dynamic v) {
    if (v == null) return null;
    final t = v.toString().trim();
    return t.isEmpty ? null : t;
  }

  (String, String) _row(String label, dynamic value) {
    final t = _trim(value);
    return (label, t ?? '');
  }
}
