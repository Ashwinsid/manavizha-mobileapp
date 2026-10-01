import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'web_api.dart';

/// Identity & address verification — Flutter port of the web's
/// `components/identity-verification-card.tsx` (Settings → ID Verification).
///
///   1. Aadhaar via DigiLocker (Cashfree): `/api/kyc/aadhaar/start` returns a
///      DigiLocker link that opens in the browser. DigiLocker returns the
///      member to the website, so the app finishes the check with
///      `/api/kyc/aadhaar/complete` when it comes back to the foreground.
///   2. If the Aadhaar address doesn't match, the member can ask for a letter
///      with a one-time code (`/api/kyc/postal`) and enter it here
///      (`/api/kyc/postal/verify`).
///
/// No Aadhaar images are uploaded and the Aadhaar number never touches the app.
class IdentityVerificationCard extends StatefulWidget {
  const IdentityVerificationCard({super.key, this.accent = const Color(0xFFD61A45)});

  final Color accent;

  @override
  State<IdentityVerificationCard> createState() => _IdentityVerificationCardState();
}

class _IdentityVerificationCardState extends State<IdentityVerificationCard> with WidgetsBindingObserver {
  Map<String, dynamic>? _status;
  bool _loading = true;
  bool _loadError = false;
  bool _busy = false;
  bool _consent = false;

  /// Set when DigiLocker was opened; the next resume completes the check.
  bool _awaitingDigiLocker = false;
  bool _checkingReturn = false;
  Map<String, dynamic>? _lastResult;

  String _postalAddress = 'permanent';
  final TextEditingController _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingDigiLocker) {
      _awaitingDigiLocker = false;
      _completeAadhaar();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    final res = await WebApi.get('/api/kyc/status');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadError = !res.ok;
      if (res.ok) {
        _status = res.data;
        final postable = _postable;
        if (postable['permanent'] != true && postable['current'] == true) _postalAddress = 'current';
      }
    });
  }

  Map<String, dynamic> get _postable {
    final p = _status?['postableAddresses'];
    return p is Map ? Map<String, dynamic>.from(p) : const {};
  }

  Map<String, dynamic>? get _openLetter {
    final p = _status?['postal'];
    if (p is! Map) return null;
    final st = p['status'];
    return (st == 'requested' || st == 'dispatched') ? Map<String, dynamic>.from(p) : null;
  }

  Future<void> _startAadhaar() async {
    setState(() => _busy = true);
    final res = await WebApi.post('/api/kyc/aadhaar/start', {'consent': _consent});
    final url = res.data['url']?.toString();
    if (!res.ok || url == null || url.isEmpty) {
      if (mounted) setState(() => _busy = false);
      _toast(res.error ?? 'Could not start Aadhaar verification');
      return;
    }
    _awaitingDigiLocker = true;
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    if (!opened) {
      _awaitingDigiLocker = false;
      _toast('Could not open DigiLocker. Please try again.');
    }
  }

  /// Back from DigiLocker: fetch the result, retrying briefly while pending.
  Future<void> _completeAadhaar() async {
    if (!mounted) return;
    setState(() => _checkingReturn = true);
    try {
      for (var attempt = 0; attempt < 5; attempt++) {
        final res = await WebApi.post('/api/kyc/aadhaar/complete', {});
        if (!res.ok) {
          _toast(res.error ?? 'Could not complete Aadhaar verification');
          return;
        }
        final state = res.data['state'];
        if (state == 'verified') {
          if (mounted) setState(() => _lastResult = res.data);
          _toast(res.data['addressVerified'] == true ? 'Identity and address verified' : 'Aadhaar verified');
          return;
        }
        if (state == 'failed') {
          _toast(res.data['error']?.toString() ?? 'Aadhaar verification did not complete');
          return;
        }
        if (state == 'none') return;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      _toast('DigiLocker is still processing. Check again in a minute.');
    } finally {
      if (mounted) setState(() => _checkingReturn = false);
      await _load();
    }
  }

  Future<void> _requestLetter() async {
    setState(() => _busy = true);
    final res = await WebApi.post('/api/kyc/postal', {'address': _postalAddress});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _toast(res.error ?? 'Could not request a letter');
      return;
    }
    _toast("Request received — we'll post a letter with your code");
    _load();
  }

  Future<void> _cancelLetter() async {
    setState(() => _busy = true);
    final res = await WebApi.delete('/api/kyc/postal', {});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) _toast(res.error ?? 'Could not cancel');
    _load();
  }

  Future<void> _submitCode() async {
    setState(() => _busy = true);
    final res = await WebApi.post('/api/kyc/postal/verify', {'code': _codeCtrl.text.trim()});
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok) {
      _toast(res.error ?? "That code isn't right");
      _load();
      return;
    }
    _codeCtrl.clear();
    _toast('Address verified');
    _load();
  }

  static String _formatAddress(dynamic a) {
    if (a is! Map) return '';
    return [a['line1'], a['line2'], a['area'], a['district'], a['state'], a['pincode']]
        .where((v) => v != null && v.toString().trim().isNotEmpty)
        .join(', ');
  }

  Widget _badge({required bool ok, bool pending = false, required String label}) {
    final (bg, fg, icon) = ok
        ? (const Color(0xFFECFDF5), const Color(0xFF16A34A), Icons.check_circle_rounded)
        : pending
            ? (const Color(0xFFFFFBEB), const Color(0xFFC9A227), Icons.schedule_rounded)
            : (const Color(0xFFF9FAFB), const Color(0xFF6B7280), Icons.cancel_outlined);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }

  Widget _note(String text, {Color bg = const Color(0xFFFAF8F4), Color? fg}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(fontSize: 13, height: 1.4, color: fg ?? const Color(0xFF4B5563))),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    final s = _status;
    if (s == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _note(_loadError
            ? "We couldn't load your verification status right now."
            : 'Verification status is unavailable.'),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            setState(() => _loading = true);
            _load();
          },
          child: const Text('Try again'),
        ),
      ]);
    }

    final aadhaarVerified = s['aadhaarVerified'] == true;
    final nameMatch = s['nameMatch'];
    final addressVerified = s['addressVerified'] == true;
    final letter = _openLetter;
    final postable = _postable;
    final canPost = postable['permanent'] == true || postable['current'] == true;
    final accent = widget.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Identity & address verification',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text('Verified members get a badge and more responses',
            style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.5))),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _badge(ok: aadhaarVerified && nameMatch != false, label: aadhaarVerified ? 'ID verified' : 'ID not verified'),
          _badge(
            ok: addressVerified,
            pending: letter != null,
            label: addressVerified
                ? 'Address verified'
                : letter != null
                    ? 'Letter on the way'
                    : 'Address not verified',
          ),
        ]),
        const SizedBox(height: 16),

        // Step 1 — Aadhaar via DigiLocker
        if (aadhaarVerified) ...[
          _note('Verified with Aadhaar XXXX XXXX ${s['aadhaarLast4'] ?? ''}.', bg: const Color(0xFFECFDF5)),
          if (nameMatch == false) ...[
            const SizedBox(height: 6),
            _note(
              "The name on your Aadhaar doesn't match your profile name, so the ID badge isn't shown. "
              'Update your profile name to match your Aadhaar and verify again.',
              bg: const Color(0xFFFFFBEB),
              fg: const Color(0xFFB45309),
            ),
          ],
        ] else if (s['aadhaarAvailable'] != true)
          _note('Aadhaar verification is coming soon.')
        else if (_checkingReturn)
          _note('Checking your DigiLocker verification…')
        else ...[
          const Text(
            "You'll be taken to DigiLocker (Government of India) to sign in with your Aadhaar number and the OTP "
            "sent to your Aadhaar-linked mobile, and to approve sharing your Aadhaar. Then come back to this app "
            'and we will finish the check.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v == true),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'I consent to Manavizha verifying my identity and address with my Aadhaar through DigiLocker, '
              'via its licensed verification partner Cashfree. Only the result, my name and the last 4 digits '
              'of my Aadhaar are stored — never the full number, photo or address.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
          Row(children: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: accent),
              onPressed: _busy || !_consent ? null : _startAadhaar,
              child: Text(_busy ? 'Opening DigiLocker…' : 'Verify with Aadhaar (DigiLocker)'),
            ),
          ]),
          TextButton(
            onPressed: _checkingReturn ? null : _completeAadhaar,
            child: const Text('I finished in DigiLocker — check now'),
          ),
        ],

        if (_lastResult != null && _lastResult!['addressVerified'] != true) ...[
          const SizedBox(height: 10),
          _note(
            "Your Aadhaar address didn't match your profile address"
            '${(_lastResult!['addressReasons'] is List && (_lastResult!['addressReasons'] as List).isNotEmpty) ? ' (${(_lastResult!['addressReasons'] as List).join('; ').toLowerCase()})' : ''}. '
            'You can correct your address in your profile and verify again, or verify it by post below.',
            bg: const Color(0xFFFFFBEB),
            fg: const Color(0xFF92400E),
          ),
        ],

        // Step 2 — address by post
        if (!addressVerified) ...[
          const Divider(height: 32),
          Row(children: [
            Icon(Icons.mail_outline_rounded, size: 18, color: accent),
            const SizedBox(width: 8),
            const Text('Verify your address by post', style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          if (letter?['status'] == 'dispatched') ...[
            Text(
              "We've posted a letter to ${_formatAddress(letter!['address'])}. Enter the code printed on it."
              '${letter['expiresAt'] != null ? ' The code is valid until ${_date(letter['expiresAt'])}.' : ''}',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  maxLength: 9,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'XXXX-XXXX', counterText: ''),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: _busy || _codeCtrl.text.replaceAll(RegExp('[^A-Za-z0-9]'), '').length != 8
                    ? null
                    : _submitCode,
                child: const Text('Submit code'),
              ),
            ]),
            Text('${letter['attemptsLeft'] ?? 0} attempts left.',
                style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45))),
          ] else if (letter?['status'] == 'requested') ...[
            Text(
              'Your request is being processed. A letter with a one-time code will be posted to '
              '${_formatAddress(letter!['address'])}.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _busy ? null : _cancelLetter, child: const Text('Cancel request')),
            ),
          ] else if (canPost) ...[
            const Text(
              "We'll post a letter with a one-time code to your address. Enter the code here when it arrives.",
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final kind in const ['permanent', 'current'])
                if (postable[kind] == true)
                  ChoiceChip(
                    label: Text(kind == 'permanent' ? 'Permanent address' : 'Current address'),
                    selected: _postalAddress == kind,
                    onSelected: (_) => setState(() => _postalAddress = kind),
                  ),
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _busy || postable[_postalAddress] != true ? null : _requestLetter,
                child: const Text('Request a letter'),
              ),
            ),
          ] else
            const Text(
              'Add your full address (door no./street, district, state and PIN code) in your profile to verify it by post.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
        ],
      ],
    );
  }

  static String _date(dynamic v) {
    final d = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
    return d == null ? '' : '${d.day}/${d.month}/${d.year}';
  }
}
