import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'app_config.dart';

/// Flutter port of [manavizha/components/manage-parents.tsx] +
/// [manavizha/app/dashboard/parents/page.tsx].
///
/// Lets a member create up to two parent accounts (Father / Mother) that are
/// linked to their `personal_details` via the [parents] table's
/// `child_user_id`. Account creation goes through the existing
/// `/api/parents` Next.js route (uses the service-role key server-side) and
/// deletion is a plain Supabase delete with RLS on `child_user_id`.
class ManageParentsScreen extends StatefulWidget {
  const ManageParentsScreen({super.key});

  @override
  State<ManageParentsScreen> createState() => _ManageParentsScreenState();
}

class _ManageParentsScreenState extends State<ManageParentsScreen> {
  static const Color _brand = AdminHomeScreen.brandPurple;
  static const Color _pageBg = Color(0xFFF8F9FE);

  bool _loading = true;
  bool _showForm = false;
  bool _creating = false;
  String? _deletingId;

  List<Map<String, dynamic>> _parents = const [];

  final _formKey = GlobalKey<FormState>();
  String? _role; // 'Father' | 'Mother'
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _parents = const [];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final rows = await Supabase.instance.client
          .from('parents')
          .select('id, child_user_id, name, email, phone, role, created_at')
          .eq('child_user_id', uid)
          .order('created_at', ascending: true);
      if (!mounted) return;
      setState(() {
        _parents = (rows as List<dynamic>? ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('ManageParents load: $e\n$st');
      if (!mounted) return;
      setState(() {
        _parents = const [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load parents')),
      );
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    setState(() {
      _role = null;
      _name.clear();
      _email.clear();
      _phone.clear();
      _password.clear();
      _showPassword = false;
    });
  }

  Future<void> _createParent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a role (Father or Mother).')),
      );
      return;
    }
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    if (!AppConfig.hasWebAppForAdminApi) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Creating parent accounts is disabled in this build (WEB_APP_BASE_URL is empty).',
          ),
        ),
      );
      return;
    }

    setState(() => _creating = true);
    final base = AppConfig.webAppBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/api/parents');
    try {
      final res = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'role': _role,
              'name': _name.text.trim(),
              'email': _email.text.trim(),
              'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
              'password': _password.text,
              'child_user_id': uid,
            }),
          )
          .timeout(const Duration(seconds: 30));

      Map<String, dynamic> map;
      try {
        map = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {
        map = {
          'error': 'Unexpected response (HTTP ${res.statusCode}).',
        };
      }

      if (res.statusCode >= 200 && res.statusCode < 300 && map['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$_role account created successfully!')),
        );
        _resetForm();
        setState(() => _showForm = false);
        await _load();
      } else {
        final err = map['error']?.toString() ?? 'Failed to create parent account';
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Network error: $e\n\nCheck that ${AppConfig.webAppBaseUrl}/api/parents is reachable.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> parent) async {
    final role = (parent['role'] as String?) ?? 'parent';
    final id = parent['id']?.toString();
    if (id == null || id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $role account?'),
        content: Text(
          'Are you sure you want to delete the $role account? They will lose '
          'access to your matches and selections.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _deletingId = id);
    try {
      await Supabase.instance.client
          .from('parents')
          .delete()
          .eq('id', id)
          .eq('child_user_id', uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$role account deleted')),
      );
      await _load();
    } catch (e, st) {
      debugPrint('ManageParents delete: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete account: $e')),
      );
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  bool get _canAddAnother {
    if (_parents.length >= 2) return false;
    final usedRoles = _parents.map((p) => (p['role'] as String?)?.toLowerCase()).toSet();
    return !usedRoles.contains('father') || !usedRoles.contains('mother');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: _pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Manage parent access',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: _brand,
            letterSpacing: -0.3,
          ),
        ),
        iconTheme: const IconThemeData(color: _brand),
        actions: [
          if (!_loading && !_showForm && _canAddAnother)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => setState(() => _showForm = true),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18, color: _brand),
                label: const Text(
                  'Add parent',
                  style: TextStyle(color: _brand, fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : RefreshIndicator(
              color: _brand,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Text(
                    'Create accounts for your parents so they can browse and '
                    'select profiles on your behalf — they get their own '
                    'sign-in and dashboard.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: Colors.black.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_showForm) _addParentCard(),
                  if (_showForm) const SizedBox(height: 18),
                  if (_parents.isEmpty)
                    _emptyState()
                  else ...[
                    for (final p in _parents) ...[
                      _parentCard(p),
                      const SizedBox(height: 12),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06), style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Icon(Icons.supervisor_account_rounded, size: 44, color: _brand.withValues(alpha: 0.55)),
          const SizedBox(height: 10),
          const Text(
            'No parent accounts yet',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Add an account to let your parents help you search for matches.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.55),
              height: 1.35,
            ),
          ),
          if (!_showForm && _canAddAnother) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => setState(() => _showForm = true),
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add parent now'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _parentCard(Map<String, dynamic> p) {
    final role = (p['role'] as String?) ?? '';
    final name = (p['name'] as String?)?.trim() ?? 'Parent';
    final email = (p['email'] as String?)?.trim() ?? '—';
    final phone = (p['phone'] as String?)?.trim();
    final created = p['created_at']?.toString();
    final createdLabel = _prettyDate(created);
    final id = p['id']?.toString() ?? '';
    final deleting = _deletingId == id;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: _brand.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 4, color: _brand),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _brand.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          role.isEmpty ? '—' : role,
                          style: const TextStyle(
                            color: _brand,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: deleting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.redAccent,
                                ),
                              )
                            : const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        tooltip: 'Delete',
                        onPressed: deleting ? null : () => _confirmDelete(p),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E1E1E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _kv('Email', email),
                  if (phone != null && phone.isNotEmpty) _kv('Phone', phone),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
                    ),
                    child: Text(
                      'Added on $createdLabel',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              '$k:',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E1E1E),
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.black.withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addParentCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _brand.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: _brand.withValues(alpha: 0.06),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.person_add_alt_1_rounded, color: _brand.withValues(alpha: 0.9)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create parent account',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'They will use the email and password below to login.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: _roleChip('Father')),
                      const SizedBox(width: 8),
                      Expanded(child: _roleChip('Mother')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    decoration: _dec('Full name *', hint: 'E.g., Ramasamy'),
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Name is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _email,
                    decoration: _dec('Email *', hint: 'parent@example.com'),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Email is required';
                      if (!t.contains('@') || !t.contains('.')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phone,
                    decoration: _dec('Mobile number', hint: '+91 9876543210'),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _password,
                    decoration: _dec(
                      'Login password *',
                      hint: 'Create a password for them',
                    ).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                    obscureText: !_showPassword,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length < 6) return 'Must be at least 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Must be at least 6 characters long.',
                    style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _creating
                            ? null
                            : () {
                                _resetForm();
                                setState(() => _showForm = false);
                              },
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _brand,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _creating ? null : _createParent,
                        child: _creating
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text('Creating…'),
                                ],
                              )
                            : const Text('Create account'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleChip(String role) {
    final selected = _role == role;
    final usedRoles = _parents.map((p) => (p['role'] as String?)?.toLowerCase()).toSet();
    final disabled = usedRoles.contains(role.toLowerCase());
    return InkWell(
      onTap: disabled ? null : () => setState(() => _role = role),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? _brand.withValues(alpha: 0.12)
              : disabled
                  ? Colors.black.withValues(alpha: 0.04)
                  : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? _brand
                : disabled
                    ? Colors.black.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.14),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              role == 'Father' ? Icons.man_rounded : Icons.woman_rounded,
              size: 18,
              color: disabled
                  ? Colors.black.withValues(alpha: 0.3)
                  : selected
                      ? _brand
                      : Colors.black.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Text(
              disabled ? '$role · added' : role,
              style: TextStyle(
                color: disabled
                    ? Colors.black.withValues(alpha: 0.4)
                    : selected
                        ? _brand
                        : const Color(0xFF1E1E1E),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
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
    );
  }

  String _prettyDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
