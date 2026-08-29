import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';

/// Edits a row in [referral_partners] using the same fields as the web
/// `ReferralPartnerProfileForm` — text columns plus KYC uploads to the
/// `referral-partners` storage bucket (partner photo, Aadhaar front/back,
/// PAN front/back), mirroring `components/referral-partner-profile-form.tsx`.
///
/// By default this screen edits the **currently signed-in user's** row, but
/// admins can pass [userId] to edit any partner's row from the Accounts
/// screen. When [userId] is provided, the app bar shows the partner's name
/// (via [heading]) and writes go to that user_id instead.
class ReferralPartnerProfileEditScreen extends StatefulWidget {
  const ReferralPartnerProfileEditScreen({
    super.key,
    this.userId,
    this.heading,
  });

  /// Optional Supabase auth user-id to edit. Defaults to the signed-in user.
  final String? userId;

  /// Optional partner name to display in the app bar (admin context).
  final String? heading;

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

  static const String _storageBucket = 'referral-partners';
  static const int _maxUploadBytes = 5 * 1024 * 1024;

  final Map<String, String> _docUrls = {
    'partner_photo': '',
    'aadhar_front': '',
    'aadhar_back': '',
    'pancard_front': '',
    'pancard_back': '',
  };
  final Map<String, String?> _signedPreview = {};
  String? _uploadingDocKey;

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

    _pincode.addListener(() async {
      if (_pincode.text.trim().length == 6 && !_loading) {
        try {
          final res = await http.get(Uri.parse('https://api.postalpincode.in/pincode/${_pincode.text.trim()}'));
          if (res.statusCode == 200) {
            final json = jsonDecode(res.body);
            if (json is List && json.isNotEmpty && json[0]['Status'] == 'Success') {
              final pos = json[0]['PostOffice'] as List?;
              if (pos != null && pos.isNotEmpty) {
                final po = pos[0];
                final name = po['Name']?.toString() ?? '';
                final block = po['Block']?.toString() ?? '';
                final district = po['District']?.toString() ?? '';
                final state = po['State']?.toString() ?? '';
                final country = po['Country']?.toString() ?? '';
                final blockStr = (block.isNotEmpty && block.toLowerCase() != 'na') ? block : district;
                final areaStr = name.isNotEmpty ? '$name ($blockStr)' : blockStr;
                
                if (mounted) {
                  setState(() {
                    _area.text = areaStr;
                    _district.text = district;
                    _state.text = state;
                    _country.text = country;
                  });
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Pincode fetch error: $e');
        }
      }
    });

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
    final uid = widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
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
      for (final k in _docUrls.keys) {
        _docUrls[k] = (m[k] as String?)?.trim() ?? '';
      }
      _signedPreview.clear();
      setState(() => _loading = false);
      await _hydrateSignedPreviews();
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
    final uid = widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    final missingDocs = <String>[];
    if (_docUrls['partner_photo']!.trim().isEmpty) missingDocs.add('Partner photo');
    if (_docUrls['aadhar_front']!.trim().isEmpty) missingDocs.add('Aadhaar front');
    if (_docUrls['aadhar_back']!.trim().isEmpty) missingDocs.add('Aadhaar back');
    if (_docUrls['pancard_front']!.trim().isEmpty) missingDocs.add('PAN front');
    if (_docUrls['pancard_back']!.trim().isEmpty) missingDocs.add('PAN back');
    if (missingDocs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please upload: ${missingDocs.join(', ')}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      // Update only these columns so document URLs and admin fields stay intact.
      final updates = <String, dynamic>{
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
        'partner_photo': _docUrls['partner_photo']!.trim(),
        'aadhar_front': _docUrls['aadhar_front']!.trim(),
        'aadhar_back': _docUrls['aadhar_back']!.trim(),
        'pancard_front': _docUrls['pancard_front']!.trim(),
        'pancard_back': _docUrls['pancard_back']!.trim(),
      };
      // The signed-in partner also keeps their email column in sync with auth.
      // Admins editing somebody else's row must not overwrite the partner's
      // email with their own.
      if (widget.userId == null) {
        final email = Supabase.instance.client.auth.currentUser?.email ?? '';
        if (email.isNotEmpty) updates['email'] = email;
      }
      await Supabase.instance.client.from('referral_partners').update(updates).eq('user_id', uid);
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

  static String? _storagePathFromPublicUrl(String url) {
    final m = RegExp(r'/storage/v1/object/public/referral-partners/(.+)$').firstMatch(url);
    return m?.group(1);
  }

  static String _mimeForExt(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _hydrateSignedPreviews() async {
    final client = Supabase.instance.client;
    for (final k in _docUrls.keys) {
      final url = _docUrls[k] ?? '';
      if (url.isEmpty || !url.startsWith('http')) continue;
      final path = _storagePathFromPublicUrl(url);
      if (path == null) {
        if (mounted) setState(() => _signedPreview[k] = url);
        continue;
      }
      try {
        final signed = await client.storage.from(_storageBucket).createSignedUrl(path, 3600);
        if (mounted) setState(() => _signedPreview[k] = signed);
      } catch (e) {
        debugPrint('Signed URL for $k: $e');
        if (mounted) setState(() => _signedPreview[k] = url);
      }
    }
  }

  Future<void> _refreshOneSigned(String key) async {
    final url = _docUrls[key] ?? '';
    if (url.isEmpty) {
      if (mounted) setState(() => _signedPreview.remove(key));
      return;
    }
    if (!url.startsWith('http')) return;
    final path = _storagePathFromPublicUrl(url);
    final client = Supabase.instance.client;
    if (path == null) {
      if (mounted) setState(() => _signedPreview[key] = url);
      return;
    }
    try {
      final signed = await client.storage.from(_storageBucket).createSignedUrl(path, 3600);
      if (mounted) setState(() => _signedPreview[key] = signed);
    } catch (_) {
      if (mounted) setState(() => _signedPreview[key] = url);
    }
  }

  Future<void> _pickAndUpload(String key) async {
    final uid = widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final client = Supabase.instance.client;

    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      imageQuality: 85,
    );
    if (x == null) return;

    var ext = x.path.contains('.') ? x.path.split('.').last.toLowerCase() : 'jpg';
    if (ext.length > 5) ext = 'jpg';
    const allowed = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif'};
    if (!allowed.contains(ext)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an image file (JPG, PNG, WebP, HEIC).')),
      );
      return;
    }

    final bytes = await x.readAsBytes();
    if (bytes.length > _maxUploadBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File size must be less than 5MB')),
      );
      return;
    }

    setState(() => _uploadingDocKey = key);
    try {
      final oldUrl = _docUrls[key] ?? '';
      final oldPath = oldUrl.startsWith('http') ? _storagePathFromPublicUrl(oldUrl) : null;
      if (oldPath != null && oldPath.isNotEmpty) {
        try {
          await client.storage.from(_storageBucket).remove([oldPath]);
        } catch (_) {}
      }

      final path = '$uid/${key}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await client.storage.from(_storageBucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(upsert: false, contentType: _mimeForExt(ext == 'jpeg' ? 'jpg' : ext)),
      );

      final publicUrl = client.storage.from(_storageBucket).getPublicUrl(path);
      if (!mounted) return;
      setState(() {
        _docUrls[key] = publicUrl;
        _uploadingDocKey = null;
      });
      await _refreshOneSigned(key);
    } catch (e, st) {
      debugPrint('Partner doc upload: $e\n$st');
      if (!mounted) return;
      setState(() => _uploadingDocKey = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  void _clearDoc(String key) {
    setState(() {
      _docUrls[key] = '';
      _signedPreview.remove(key);
    });
  }

  Widget _buildDocumentRow({
    required String storageKey,
    required String title,
    required String subtitle,
  }) {
    final busy = _uploadingDocKey == storageKey;
    final url = _docUrls[storageKey] ?? '';
    final preview = _signedPreview[storageKey] ?? url;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.5))),
              const SizedBox(height: 10),
              if (preview.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    preview,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 100,
                      alignment: Alignment.center,
                      color: Colors.grey.shade200,
                      child: const Text('Could not load preview'),
                    ),
                  ),
                )
              else
                Container(
                  height: 88,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                  ),
                  child: Text('No file yet', style: TextStyle(color: Colors.black.withValues(alpha: 0.45))),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: busy ? null : () => _pickAndUpload(storageKey),
                    child: busy
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 10),
                              Text('Uploading…'),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.upload_rounded, size: 18),
                              const SizedBox(width: 8),
                              Text(url.isEmpty ? 'Upload' : 'Replace'),
                            ],
                          ),
                  ),
                  if (url.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _clearDoc(storageKey),
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Remove'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
        title: Text(
          widget.heading != null && widget.heading!.trim().isNotEmpty
              ? 'Edit: ${widget.heading!.trim()}'
              : 'Edit partner profile',
          style: const TextStyle(fontWeight: FontWeight.w800, color: _brandPurple, letterSpacing: -0.3),
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
                      const SizedBox(height: 28),
                      Text(
                        'KYC & documents',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: Colors.black.withValues(alpha: 0.45),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Upload clear photos (max 5MB each). Same storage bucket and public URLs as the website (`referral-partners`). All five are required before save.',
                        style: TextStyle(fontSize: 12, height: 1.35, color: Colors.black.withValues(alpha: 0.45)),
                      ),
                      const SizedBox(height: 12),
                      _buildDocumentRow(
                        storageKey: 'partner_photo',
                        title: 'Partner photo *',
                        subtitle: 'A recent portrait for your partner profile.',
                      ),
                      _buildDocumentRow(
                        storageKey: 'aadhar_front',
                        title: 'Aadhaar front *',
                        subtitle: 'Front side of your Aadhaar card.',
                      ),
                      _buildDocumentRow(
                        storageKey: 'aadhar_back',
                        title: 'Aadhaar back *',
                        subtitle: 'Back side of your Aadhaar card.',
                      ),
                      _buildDocumentRow(
                        storageKey: 'pancard_front',
                        title: 'PAN card front *',
                        subtitle: 'Front of your PAN card.',
                      ),
                      _buildDocumentRow(
                        storageKey: 'pancard_back',
                        title: 'PAN card back *',
                        subtitle: 'Back of your PAN card.',
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
