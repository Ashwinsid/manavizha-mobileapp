import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_home_screen.dart';

/// Admin **Email tools** screen.
///
/// The web at `app/admin/dashboard/email/page.tsx` is a stub today (only a
/// "Email management content will go here..." placeholder). There is no
/// Resend/SES/SMTP integration in either project, so this Flutter screen
/// ships the first working version of the feature using the OS mail client:
///
///  1. Pick an audience using the filters (gender, premium, marital status,
///     referral partner, free-text search). All filters are joined to the
///     `users` / `personal_details` / `user_settings` / `referral_details`
///     tables that the admin Manage Profiles screen already uses, so the
///     numbers match the rest of the admin area.
///  2. Preview the resulting recipient count + the first few rows so the
///     admin knows what they're about to send to.
///  3. Compose a Subject + Body.
///  4. Send via the device mail client. The recipients go in BCC (so users
///     don't see each other), and the list is chunked into batches of 50
///     because `mailto:` URI length limits can truncate longer headers on
///     some platforms. Each batch opens the user's default mail app with
///     subject + body pre-filled — the admin just hits Send for each batch.
///  5. Optionally, "Copy emails" puts a comma-separated list of all matched
///     emails on the clipboard so the admin can paste them into Gmail /
///     Outlook BCC manually if `mailto:` is undesirable.
class AdminEmailScreen extends StatefulWidget {
  const AdminEmailScreen({super.key});

  @override
  State<AdminEmailScreen> createState() => _AdminEmailScreenState();
}

class _AdminEmailScreenState extends State<AdminEmailScreen> {
  static const Color _brand = AdminHomeScreen.brandPurple;
  static const Color _pageBg = Color(0xFFF8F9FE);

  static const int _mailtoBatchSize = 50;
  static const int _maxRecipients = 1000;

  bool _loading = true;
  bool _refreshing = false;
  String? _loadError;

  // Audience filters
  String _gender = 'any'; // any / male / female
  String _premium = 'any'; // any / yes / no
  String _marital = 'any'; // any / single / married / divorced / widowed
  String? _partnerId; // referral_partners.partner_id

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _subjectCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();

  Timer? _debounce;

  List<_PartnerOption> _partners = [];
  List<_Recipient> _recipients = [];
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _refreshRecipients);
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final client = Supabase.instance.client;
      final partnerRows = await client
          .from('referral_partners')
          .select('partner_id, name')
          .not('partner_id', 'is', null)
          .order('name', ascending: true);
      _partners = [
        for (final row in (partnerRows as List<dynamic>))
          _PartnerOption(
            id: (row as Map)['partner_id']?.toString() ?? '',
            name: ((row)['name'] as String?)?.trim().isNotEmpty == true
                ? (row['name'] as String).trim()
                : 'Unnamed partner',
          ),
      ].where((p) => p.id.isNotEmpty).toList();
      await _refreshRecipients();
      if (mounted) setState(() => _loading = false);
    } catch (e, st) {
      debugPrint('AdminEmail bootstrap error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _refreshRecipients() async {
    if (!mounted) return;
    setState(() => _refreshing = true);
    try {
      final client = Supabase.instance.client;

      // 1) Pull personal_details rows that match the gender + marital filter.
      var personalQuery =
          client.from('personal_details').select('user_id, name, sex, marital_status');
      if (_gender != 'any') {
        personalQuery = personalQuery.ilike('sex', _gender);
      }
      if (_marital != 'any') {
        personalQuery = personalQuery.ilike('marital_status', _marital);
      }
      final personalRes = await personalQuery.limit(_maxRecipients);
      final personalRows = (personalRes as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      var candidateIds = personalRows.map((m) => m['user_id'] as String?).whereType<String>().toSet();

      // 2) Restrict to the selected referral partner if any.
      if (_partnerId != null) {
        final refRes = await client
            .from('referral_details')
            .select('user_id')
            .eq('referral_partner_id', _partnerId!);
        final partnerIds = (refRes as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map)['user_id'] as String?)
            .whereType<String>()
            .toSet();
        candidateIds = candidateIds.intersection(partnerIds);
      }

      // 3) Pull users rows in chunks (.in_ accepts ~1000).
      final ids = candidateIds.toList();
      final userMap = <String, Map<String, dynamic>>{};
      const chunk = 200;
      for (var i = 0; i < ids.length; i += chunk) {
        final slice = ids.sublist(i, (i + chunk).clamp(0, ids.length));
        if (slice.isEmpty) continue;
        final usersRes = await client
            .from('users')
            .select('id, email, name')
            .inFilter('id', slice);
        for (final row in usersRes as List<dynamic>) {
          final m = Map<String, dynamic>.from(row as Map);
          final id = m['id']?.toString();
          final email = (m['email'] as String?)?.trim() ?? '';
          if (id != null && email.isNotEmpty && _looksLikeEmail(email)) {
            userMap[id] = m;
          }
        }
      }

      // 4) Premium filter via user_settings.
      if (_premium != 'any' && userMap.isNotEmpty) {
        final wantPremium = _premium == 'yes';
        final settingsIds = userMap.keys.toList();
        final settingsMap = <String, bool>{};
        for (var i = 0; i < settingsIds.length; i += chunk) {
          final slice = settingsIds.sublist(i, (i + chunk).clamp(0, settingsIds.length));
          if (slice.isEmpty) continue;
          final settingsRes = await client
              .from('user_settings')
              .select('user_id, is_premium')
              .inFilter('user_id', slice);
          for (final row in settingsRes as List<dynamic>) {
            final m = Map<String, dynamic>.from(row as Map);
            final uid = m['user_id']?.toString();
            if (uid != null) settingsMap[uid] = m['is_premium'] == true;
          }
        }
        userMap.removeWhere((id, _) => (settingsMap[id] ?? false) != wantPremium);
      }

      // 5) Free-text search filter (matches name OR email).
      final q = _searchCtrl.text.trim().toLowerCase();
      final recipientList = <_Recipient>[];
      final personalById = {
        for (final p in personalRows) (p['user_id'] as String? ?? ''): p,
      };
      for (final entry in userMap.entries) {
        final id = entry.key;
        final u = entry.value;
        final email = (u['email'] as String).trim();
        var name = (u['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) {
          name = (personalById[id]?['name'] as String?)?.trim() ?? '';
        }
        if (q.isNotEmpty) {
          if (!name.toLowerCase().contains(q) && !email.toLowerCase().contains(q)) {
            continue;
          }
        }
        recipientList.add(_Recipient(id: id, name: name, email: email));
      }
      recipientList.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _recipients = recipientList;
        _totalCount = recipientList.length;
        _refreshing = false;
      });
    } catch (e, st) {
      debugPrint('AdminEmail refresh error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _loadError = e.toString();
      });
    }
  }

  static bool _looksLikeEmail(String s) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s);
  }

  String _audienceLabel() {
    final bits = <String>[];
    bits.add(_gender == 'any' ? 'everyone' : (_gender == 'male' ? 'men' : 'women'));
    if (_premium == 'yes') bits.add('premium');
    if (_premium == 'no') bits.add('non-premium');
    if (_marital != 'any') bits.add(_marital);
    if (_partnerId != null) {
      final p = _partners.firstWhere(
        (p) => p.id == _partnerId,
        orElse: () => _PartnerOption(id: '', name: 'partner'),
      );
      bits.add('via ${p.name}');
    }
    if (_searchCtrl.text.trim().isNotEmpty) {
      bits.add('matching "${_searchCtrl.text.trim()}"');
    }
    return bits.join(' · ');
  }

  Future<void> _onSend() async {
    if (_subjectCtrl.text.trim().isEmpty && _bodyCtrl.text.trim().isEmpty) {
      _toast('Add a subject or body before sending.');
      return;
    }
    if (_recipients.isEmpty) {
      _toast('No recipients match these filters.');
      return;
    }
    if (_recipients.length > _maxRecipients) {
      _toast('Too many recipients (cap is $_maxRecipients). Narrow the filters first.');
      return;
    }

    final batches = <List<_Recipient>>[];
    for (var i = 0; i < _recipients.length; i += _mailtoBatchSize) {
      batches.add(_recipients.sublist(i, (i + _mailtoBatchSize).clamp(0, _recipients.length)));
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open mail app?'),
        content: Text(
          'This will open your default mail app ${batches.length} time(s) — once '
          'per batch of up to $_mailtoBatchSize recipients (total '
          '${_recipients.length}). Subject and body are pre-filled; just hit '
          'Send in your mail app for each batch.',
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _brand),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open mail app'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    for (var i = 0; i < batches.length; i++) {
      final batch = batches[i];
      final uri = Uri(
        scheme: 'mailto',
        path: '',
        queryParameters: {
          'bcc': batch.map((r) => r.email).join(','),
          'subject': _subjectCtrl.text.trim(),
          'body': _bodyCtrl.text,
        },
      );
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok) {
          if (!mounted) return;
          _toast('Mail app refused to open batch ${i + 1}.');
          break;
        }
      } catch (e) {
        if (!mounted) return;
        _toast('Could not open mail app: $e');
        break;
      }
      // Small pause so the OS picker has time to settle between launches.
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }

    if (!mounted) return;
    _toast(batches.length == 1
        ? 'Mail app opened with ${_recipients.length} recipient${_recipients.length == 1 ? "" : "s"}.'
        : '${batches.length} mail drafts opened in your mail app.');
  }

  Future<void> _onCopyEmails() async {
    if (_recipients.isEmpty) {
      _toast('No emails to copy.');
      return;
    }
    final csv = _recipients.map((r) => r.email).join(', ');
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    _toast('${_recipients.length} email${_recipients.length == 1 ? "" : "s"} copied to clipboard.');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- UI ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: _brand,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Row(
          children: [
            Icon(Icons.mail_outline_rounded, color: _brand),
            SizedBox(width: 10),
            Text(
              'Email',
              style: TextStyle(fontWeight: FontWeight.w800, color: _brand, fontSize: 20),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: _brand,
            tooltip: 'Refresh',
            onPressed: _loading || _refreshing ? null : _refreshRecipients,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _bootstrap, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    _sectionTitle('Audience'),
                    const SizedBox(height: 8),
                    _cardWrap(child: _buildFilters()),
                    const SizedBox(height: 16),
                    _sectionTitle('Recipients'),
                    const SizedBox(height: 8),
                    _cardWrap(child: _buildRecipients()),
                    const SizedBox(height: 16),
                    _sectionTitle('Compose'),
                    const SizedBox(height: 8),
                    _cardWrap(child: _buildComposer()),
                    const SizedBox(height: 20),
                    _buildActionRow(),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade100),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.amber.shade800, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No SMTP/Resend integration yet. Sending opens your '
                              'OS mail client with the recipients in BCC (batches '
                              'of $_mailtoBatchSize). You can also Copy emails and '
                              'paste them into Gmail / Outlook directly.',
                              style: TextStyle(fontSize: 12, height: 1.4, color: Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
        color: Colors.black.withValues(alpha: 0.55),
      ),
    );
  }

  Widget _cardWrap({required Widget child}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filterRowLabel('Gender'),
        Wrap(
          spacing: 8,
          children: [
            _segChip('Any', _gender == 'any', () => _setGender('any')),
            _segChip('Men', _gender == 'male', () => _setGender('male')),
            _segChip('Women', _gender == 'female', () => _setGender('female')),
          ],
        ),
        const SizedBox(height: 10),
        _filterRowLabel('Premium'),
        Wrap(
          spacing: 8,
          children: [
            _segChip('Any', _premium == 'any', () => _setPremium('any')),
            _segChip('Premium', _premium == 'yes', () => _setPremium('yes')),
            _segChip('Non-premium', _premium == 'no', () => _setPremium('no')),
          ],
        ),
        const SizedBox(height: 10),
        _filterRowLabel('Marital status'),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final v in const ['any', 'single', 'married', 'divorced', 'widowed'])
              _segChip(
                v == 'any' ? 'Any' : v[0].toUpperCase() + v.substring(1),
                _marital == v,
                () => _setMarital(v),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _filterRowLabel('Referred by partner'),
        InputDecorator(
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: _partnerId,
              hint: const Text('Any partner'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Any partner')),
                for (final p in _partners)
                  DropdownMenuItem<String?>(
                    value: p.id,
                    child: Text('${p.name} (${p.id})', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => _setPartnerId(v),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _filterRowLabel('Search'),
        TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Match name or email…',
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchCtrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      _onSearchChanged();
                    },
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _filterRowLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  Widget _segChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: _brand.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: selected ? _brand : Colors.black.withValues(alpha: 0.7),
      ),
      side: BorderSide(color: selected ? _brand : Colors.black.withValues(alpha: 0.1)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  void _setGender(String v) {
    setState(() => _gender = v);
    _refreshRecipients();
  }

  void _setPremium(String v) {
    setState(() => _premium = v);
    _refreshRecipients();
  }

  void _setMarital(String v) {
    setState(() => _marital = v);
    _refreshRecipients();
  }

  void _setPartnerId(String? v) {
    setState(() => _partnerId = v);
    _refreshRecipients();
  }

  Widget _buildRecipients() {
    final preview = _recipients.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _refreshing
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _brand),
                  )
                : Icon(Icons.groups_rounded, color: _brand, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$_totalCount recipient${_totalCount == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    if (_totalCount > 0)
                      TextSpan(
                        text: '   ${_audienceLabel()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
        if (_totalCount == 0) ...[
          const SizedBox(height: 8),
          Text(
            'No users match these filters.',
            style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.5)),
          ),
        ] else ...[
          const SizedBox(height: 10),
          for (final r in preview)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: _brand.withValues(alpha: 0.12),
                    child: Text(
                      r.name.isNotEmpty ? r.name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _brand),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.name.isEmpty ? r.email : '${r.name} — ${r.email}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (_totalCount > preview.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+ ${_totalCount - preview.length} more',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
            ),
          if (_totalCount >= _maxRecipients)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Capped at $_maxRecipients. Narrow the filters to include everyone.',
                style: TextStyle(fontSize: 11, color: Colors.amber.shade800, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildComposer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _subjectCtrl,
          decoration: InputDecoration(
            labelText: 'Subject',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _bodyCtrl,
          maxLines: 8,
          minLines: 5,
          decoration: InputDecoration(
            labelText: 'Message',
            alignLabelWithHint: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildActionRow() {
    final canSend = _totalCount > 0 &&
        _totalCount <= _maxRecipients &&
        (_subjectCtrl.text.trim().isNotEmpty || _bodyCtrl.text.trim().isNotEmpty);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _totalCount == 0 ? null : _onCopyEmails,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy emails'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _brand,
              side: BorderSide(color: _brand.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: canSend ? _onSend : null,
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Open mail app'),
          ),
        ),
      ],
    );
  }
}

class _PartnerOption {
  _PartnerOption({required this.id, required this.name});
  final String id;
  final String name;
}

class _Recipient {
  _Recipient({required this.id, required this.name, required this.email});
  final String id;
  final String name;
  final String email;
}
