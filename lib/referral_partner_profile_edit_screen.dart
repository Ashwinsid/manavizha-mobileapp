import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';

/// Edits the signed-in user's row in [referral_partners] (same data as the web
/// ReferralPartnerProfileForm — text fields; document uploads remain on the site).
class ReferralPartnerProfileEditScreen extends StatefulWidget {
  const ReferralPartnerProfileEditScreen({super.key});

  @override
  State<ReferralPartnerProfileEditScreen> createState() => _ReferralPartnerProfileEditScreenState();
}

class _ReferralPartnerProfileEditScreenState extends State<ReferralPartnerProfileEditScreen> {
  static const Color _brandPurple = AdminHomeScreen.brandPurple;
  static const Color _pageBg = Color(0xFFF8F9FE);

  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  String? _loadError;

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _whatsapp;
  late final TextEditingController _company;
  late final TextEditingController _orgType;
  late final TextEditingController _addr1;
  late final TextEditingController _addr2;
  late final TextEditingController _area;
  late final TextEditingController _taluk;
  late final TextEditingController _district;
  late final TextEditingController _division;
  late final TextEditingController _region;
  late final TextEditingController _city;
  late final TextEditingController _state;
  late final TextEditingController _pincode;
  late final TextEditingController _country;
  late final TextEditingController _accountNumber;
  late final TextEditingController _accountHolder;
  late final TextEditingController _ifsc;
  late final TextEditingController _branch;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _phone = TextEditingController(text: '+91');
    _whatsapp = TextEditingController(text: '+91');
    _company = TextEditingController();
    _orgType = TextEditingController();
    _addr1 = TextEditingController();
    _addr2 = TextEditingController();
    _area = TextEditingController();
    _taluk = TextEditingController();
    _district = TextEditingController();
    _division = TextEditingController();
    _region = TextEditingController();
    _city = TextEditingController();
    _state = TextEditingController();
    _pincode = TextEditingController();
    _country = TextEditingController(text: 'India');
    _accountNumber = TextEditingController();
    _accountHolder = TextEditingController();
    _ifsc = TextEditingController();
    _branch = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _whatsapp.dispose();
    _company.dispose();
    _orgType.dispose();
    _addr1.dispose();
    _addr2.dispose();
    _area.dispose();
    _taluk.dispose();
    _district.dispose();
    _division.dispose();
    _region.dispose();
    _city.dispose();
    _state.dispose();
    _pincode.dispose();
    _country.dispose();
    _accountNumber.dispose();
    _accountHolder.dispose();
    _ifsc.dispose();
    _branch.dispose();
    super.dispose();
  }

  String _phoneWithPrefix(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '+91';
    if (t.startsWith('+')) return t;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '+91';
    return digits.length <= 10 ? '+91$digits' : '+$digits';
  }

  Future<void> _load() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() {
        _loading = false;
        _loadError = 'Not signed in.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final row = await Supabase.instance.client
          .from('referral_partners')
          .select('*')
          .eq('user_id', uid)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        setState(() {
          _loading = false;
          _loadError = 'No referral partner profile is linked to this account.';
        });
        return;
      }
      final m = Map<String, dynamic>.from(row as Map);
      _name.text = (m['name'] as String?)?.trim() ?? '';
      _phone.text = _phoneWithPrefix((m['phone'] as String?) ?? '');
      _whatsapp.text = _phoneWithPrefix((m['whatsapp_number'] as String?) ?? '');
      _company.text = (m['company_name'] as String?)?.trim() ?? '';
      _orgType.text = (m['organization_type'] as String?)?.trim() ?? '';
      _addr1.text = (m['address_line1'] as String?)?.trim() ?? '';
      _addr2.text = (m['address_line2'] as String?)?.trim() ?? '';
      _area.text = (m['area'] as String?)?.trim() ?? '';
      _taluk.text = (m['taluk'] as String?)?.trim() ?? '';
      _district.text = (m['district'] as String?)?.trim() ?? '';
      _division.text = (m['division'] as String?)?.trim() ?? '';
      _region.text = (m['region'] as String?)?.trim() ?? '';
      _city.text = (m['city'] as String?)?.trim() ?? '';
      _state.text = (m['state'] as String?)?.trim() ?? '';
      _pincode.text = (m['pincode'] as String?)?.trim() ?? '';
      _country.text = (m['country'] as String?)?.trim().isNotEmpty == true
          ? m['country'].toString().trim()
          : 'India';
      _accountNumber.text = (m['account_number'] as String?)?.trim() ?? '';
      _accountHolder.text = (m['account_holder_name'] as String?)?.trim() ?? '';
      _ifsc.text = (m['ifsc_code'] as String?)?.trim() ?? '';
      _branch.text = (m['branch_name'] as String?)?.trim() ?? '';
      setState(() => _loading = false);
    } catch (e, st) {
      debugPrint('ReferralPartnerProfileEdit load: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load your partner profile.';
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    if (uid == null) return;

    setState(() => _saving = true);
    try {
      // Update only these columns so document URLs and admin fields stay intact.
      await Supabase.instance.client.from('referral_partners').update({
        'email': email,
        'name': _name.text.trim(),
        'phone': _phoneWithPrefix(_phone.text),
        'whatsapp_number': _phoneWithPrefix(_whatsapp.text),
        'company_name': _company.text.trim(),
        'organization_type': _orgType.text.trim(),
        'address_line1': _addr1.text.trim(),
        'address_line2': _addr2.text.trim(),
        'area': _area.text.trim(),
        'taluk': _taluk.text.trim(),
        'district': _district.text.trim(),
        'division': _division.text.trim(),
        'region': _region.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim(),
        'pincode': _pincode.text.trim(),
        'country': _country.text.trim().isEmpty ? 'India' : _country.text.trim(),
        'account_number': _accountNumber.text.trim(),
        'account_holder_name': _accountHolder.text.trim(),
        'ifsc_code': _ifsc.text.trim(),
        'branch_name': _branch.text.trim(),
      }).eq('user_id', uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partner profile saved'), behavior: SnackBarBehavior.floating),
      );
      Navigator.of(context).pop(true);
    } catch (e, st) {
      debugPrint('ReferralPartnerProfileEdit save: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e'), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.white,
    );
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
          'Edit partner profile',
          style: TextStyle(fontWeight: FontWeight.w800, color: _brandPurple, letterSpacing: -0.3),
        ),
        iconTheme: const IconThemeData(color: _brandPurple),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brandPurple))
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_loadError!, textAlign: TextAlign.center),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      Text(
                        'Basic',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _name,
                        decoration: _dec('Full name *'),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            (v == null || v.trim().length < 2) ? 'Enter at least 2 characters' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        decoration: _dec('Phone *', hint: '+91…'),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _whatsapp,
                        decoration: _dec('WhatsApp', hint: '+91…'),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _company,
                        decoration: _dec('Company name'),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _orgType,
                        decoration: _dec('Organization type'),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Address',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addr1,
                        decoration: _dec('Address line 1'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addr2,
                        decoration: _dec('Address line 2'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _area,
                        decoration: _dec('Area'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(controller: _taluk, decoration: _dec('Taluk')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _city, decoration: _dec('City')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _district, decoration: _dec('District')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _division, decoration: _dec('Division')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _region, decoration: _dec('Region')),
                      const SizedBox(height: 12),
                      TextFormField(controller: _state, decoration: _dec('State')),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _pincode,
                        decoration: _dec('Pincode'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(controller: _country, decoration: _dec('Country')),
                      const SizedBox(height: 28),
                      Text(
                        'Bank',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _accountHolder,
                        decoration: _dec('Account holder name'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _accountNumber,
                        decoration: _dec('Account number'),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _ifsc,
                        decoration: _dec('IFSC code'),
                        textCapitalization: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _branch,
                        decoration: _dec('Branch name'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Photo and document uploads match the website profile form; you can complete them there if needed.',
                        style: TextStyle(fontSize: 12, height: 1.35, color: Colors.black.withValues(alpha: 0.45)),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: _brandPurple,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
    );
  }
}
