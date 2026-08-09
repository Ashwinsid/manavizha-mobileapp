import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart' as pw_color;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'astrology.dart' as astro;
import 'horoscope_location_options.dart';
import 'profile_extended_details.dart' show ProfileExtendedRepository;
import 'widgets/south_indian_chart.dart';

const _kHoroscopeQuickCities = <String>[
  'Ariyalur', 'Chengalpattu', 'Chennai', 'Coimbatore', 'Cuddalore', 'Dharmapuri',
  'Dindigul', 'Erode', 'Kallakurichi', 'Kanchipuram', 'Kanyakumari', 'Karur',
  'Krishnagiri', 'Madurai', 'Mayiladuthurai', 'Nagapattinam', 'Namakkal',
  'Nilgiris', 'Perambalur', 'Pudukkottai', 'Ramanathapuram', 'Ranipet',
  'Salem', 'Sivaganga', 'Tenkasi', 'Thanjavur', 'Theni', 'Thoothukudi',
  'Tiruchirappalli', 'Tirunelveli', 'Tirupathur', 'Tiruppur', 'Tiruvallur',
  'Tiruvannamalai', 'Tiruvarur', 'Vellore', 'Viluppuram', 'Virudhunagar',
];

/// Flutter port of [manavizha/app/horoscope/page.tsx] — Vedic horoscope
/// generator. Uses the mean-motion engine from [astrology.dart] (matching
/// the web's `vedic-astro` *fallback* code path), provides a 12×11 manual
/// grid editor and a PDF download via `printing` / `pdf`.
///
/// What is **not** ported (intentionally — see FEATURE_PARITY row):
/// • Tesseract OCR upload (no Dart equivalent without native bindings).
/// • High-precision sidereal ephemeris (no Dart port of `vedic-astro`).
class HoroscopeScreen extends StatefulWidget {
  const HoroscopeScreen({
    super.key,
    this.initialName,
    this.initialDob,
    this.initialTob,
    this.initialCity,
    this.initialState,
    this.initialCountry,
    this.onSaveToProfile,
    this.allowSaveToProfile = false,
    this.memberMode = false,
  });

  final String? initialName;
  final DateTime? initialDob;
  final TimeOfDay? initialTob;
  final String? initialCity;
  final String? initialState;
  final String? initialCountry;

  /// When provided, "Save to my profile" appears in the result toolbar.
  /// Invoked with the chosen result so the caller (`profile_extended_details.dart`)
  /// can write star/rashi/lagnam back into `horoscope_details`.
  final void Function(HoroscopeSaveResult result)? onSaveToProfile;
  final bool allowSaveToProfile;

  /// Mirrors the web `app/dashboard/horoscope/page.tsx`: when `true` the
  /// screen auto-loads the signed-in user's `personal_details` (name, DOB)
  /// and `horoscope_details` (TOB, place + state + country) on mount, and
  /// the result toolbar exposes a **Save Thirukanitham/Vakkiyam to Profile**
  /// button that upserts a full payload (`star`, `zodiac_sign`, `lagnam`,
  /// `time_of_birth`, `place_of_birth`, `birth_state`, `birth_country`,
  /// `manual_grid`, `dhosham`) directly to `horoscope_details`.
  final bool memberMode;

  @override
  State<HoroscopeScreen> createState() => _HoroscopeScreenState();
}

class HoroscopeSaveResult {
  const HoroscopeSaveResult({
    required this.star,
    required this.rashi,
    required this.lagnam,
    required this.method,
    required this.timeOfBirth,
    required this.placeOfBirth,
    this.dobIso,
  });
  final String star;
  final String rashi;
  final String lagnam;
  final String method;
  final String timeOfBirth;
  final String placeOfBirth;
  final String? dobIso;
}

enum _EntryMode { auto, manual }

class _HoroscopeScreenState extends State<HoroscopeScreen> {
  static const Color _brand = AdminHomeScreen.brandPurple;
  static const Color _pageBg = Color(0xFFF8F9FE);

  late final TextEditingController _name;
  late final TextEditingController _city;
  late final TextEditingController _lat;
  late final TextEditingController _lon;
  String? _state;
  String? _country;
  DateTime? _dob;
  TimeOfDay? _tob;
  _EntryMode _mode = _EntryMode.auto;
  String _method = 'thirukanitham';
  bool _generating = false;
  bool _saving = false;
  bool _showLatLon = false;

  astro.HoroscopeDetails? _thirukanithamResult;
  astro.HoroscopeDetails? _vakkiyamResult;

  // Manual placements: planet abbreviation → set of houses 0..11
  late Map<String, Set<int>> _manual;
  String _activeManualPlanet = 'ல';

  bool _memberLoading = false;
  bool _memberSaving = false;
  String? _memberUserId;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName ?? '');
    _city = TextEditingController(
      text: widget.initialCity?.trim().isNotEmpty == true
          ? widget.initialCity!.trim()
          : 'Chennai',
    );
    _lat = TextEditingController(text: '13.0827');
    _lon = TextEditingController(text: '80.2707');
    _state = _matchOption(widget.initialState, kIndianStatesAndUTs) ?? 'Tamil Nadu';
    _country = _matchOption(widget.initialCountry, kWorldCountries) ?? 'India';
    _dob = widget.initialDob;
    _tob = widget.initialTob ?? const TimeOfDay(hour: 12, minute: 0);
    _manual = {for (final p in astro.planets) p.abbr: <int>{}};
    if (widget.memberMode) {
      _memberLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromCurrentMember());
    }
  }

  /// Direct Dart equivalent of `getProfile()` in
  /// `app/dashboard/horoscope/page.tsx` — reads name + DOB from
  /// `personal_details` and TOB + place fields from `horoscope_details`.
  /// We skip the Nominatim geocode the web does for lat/lon because that
  /// step is not user-visible (the result PoB string just carries forward
  /// what we already saved).
  Future<void> _loadFromCurrentMember() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _memberLoading = false);
      return;
    }
    _memberUserId = uid;
    try {
      final personal = await client
          .from('personal_details')
          .select('name, date_of_birth')
          .eq('user_id', uid)
          .maybeSingle();
      final horo = await client
          .from('horoscope_details')
          .select('time_of_birth, place_of_birth, birth_state, birth_country')
          .eq('user_id', uid)
          .maybeSingle();

      DateTime? dob;
      final dobStr = personal?['date_of_birth']?.toString();
      if (dobStr != null && dobStr.trim().isNotEmpty) {
        try {
          dob = DateTime.parse(dobStr.trim());
        } catch (_) {}
      }

      TimeOfDay? tob;
      final tobStr = horo?['time_of_birth']?.toString();
      if (tobStr != null && tobStr.trim().isNotEmpty) {
        final parts = tobStr.trim().split(':');
        if (parts.length >= 2) {
          final h = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          if (h != null && m != null) {
            tob = TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
          }
        }
      }

      // `place_of_birth` is composed as "City, State, Country" by the edit
      // sheet — split off the leading city segment for the form input.
      String? city;
      final pob = horo?['place_of_birth']?.toString();
      if (pob != null && pob.trim().isNotEmpty) {
        city = pob.split(',').first.trim();
      }
      final birthState = _matchOption(horo?['birth_state']?.toString(), kIndianStatesAndUTs);
      final birthCountry = _matchOption(horo?['birth_country']?.toString(), kWorldCountries);

      if (!mounted) return;
      setState(() {
        if (personal?['name']?.toString().trim().isNotEmpty == true) {
          _name.text = personal!['name'].toString().trim();
        }
        if (dob != null) _dob = dob;
        if (tob != null) _tob = tob;
        if (city != null && city.isNotEmpty) _city.text = city;
        if (birthState != null) _state = birthState;
        if (birthCountry != null) _country = birthCountry;
        _memberLoading = false;
      });
    } catch (e, st) {
      debugPrint('Horoscope member-mode load failed: $e\n$st');
      if (mounted) setState(() => _memberLoading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  String? _matchOption(String? raw, List<String> options) {
    final t = raw?.trim();
    if (t == null || t.isEmpty) return null;
    return options.contains(t) ? t : null;
  }

  astro.HoroscopeDetails? get _active =>
      _method == 'thirukanitham' ? _thirukanithamResult : _vakkiyamResult;

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final initial = _dob ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickTob() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _tob ?? const TimeOfDay(hour: 12, minute: 0),
    );
    if (picked != null) setState(() => _tob = picked);
  }

  Map<int, List<String>> _planetsByHouseFromResult(
    astro.HoroscopeDetails? r,
    bool useNavamsam,
  ) {
    final out = <int, List<String>>{};
    if (r == null) return out;
    for (final p in r.planets) {
      final h = useNavamsam ? p.navamsamIndex : p.rasiIndex;
      out.putIfAbsent(h, () => []).add(p.tamilAbbr);
    }
    return out;
  }

  Map<int, List<String>> _planetsByHouseFromManual() {
    final out = <int, List<String>>{};
    _manual.forEach((abbr, houses) {
      for (final h in houses) {
        out.putIfAbsent(h, () => []).add(abbr);
      }
    });
    return out;
  }

  void _clearManual() {
    setState(() => _manual = {for (final p in astro.planets) p.abbr: <int>{}});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Manual placements cleared')),
    );
  }

  Future<void> _generate() async {
    if (_mode == _EntryMode.manual) {
      // Match web behaviour: just preview the manual grid (no engine call).
      setState(() {
        _thirukanithamResult = astro.buildManualHoroscope();
        _vakkiyamResult = astro.buildManualHoroscope();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manual chart ready for use!')),
      );
      return;
    }
    if (_dob == null || _tob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both date and time of birth.')),
      );
      return;
    }
    final lat = double.tryParse(_lat.text.trim()) ?? 13.0827;
    final lon = double.tryParse(_lon.text.trim()) ?? 80.2707;
    setState(() => _generating = true);
    try {
      final birth = DateTime(
        _dob!.year,
        _dob!.month,
        _dob!.day,
        _tob!.hour,
        _tob!.minute,
      );
      final location = astro.Location(latitude: lat, longitude: lon);
      // Default IST offset; the web uses tz-lookup for non-IN coords but
      // we keep this scoped — see FEATURE_PARITY note.
      const tz = Duration(hours: 5, minutes: 30);
      final thiru = astro.generateHoroscope(
        birthLocalDate: birth,
        location: location,
        timezoneOffset: tz,
        method: 'thirukanitham',
      );
      final vakk = astro.generateHoroscope(
        birthLocalDate: birth,
        location: location,
        timezoneOffset: tz,
        method: 'vakkiyam',
      );

      // Sync manual placements from the auto result so users can tweak.
      final synced = {for (final p in astro.planets) p.abbr: <int>{}};
      for (final p in thiru.planets) {
        synced.putIfAbsent(p.tamilAbbr, () => <int>{}).add(p.rasiIndex);
      }
      if (!mounted) return;
      setState(() {
        _thirukanithamResult = thiru;
        _vakkiyamResult = vakk;
        _manual = synced;
        _generating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Horoscope calculated. You can tweak the grid in Manual mode.')),
      );
    } catch (e, st) {
      debugPrint('Horoscope generate failed: $e\n$st');
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Calculation failed: $e')),
      );
    }
  }

  void _toggleManual(String abbr, int house) {
    setState(() {
      final set = _manual[abbr] ??= <int>{};
      if (set.contains(house)) {
        set.remove(house);
      } else {
        set.add(house);
      }
    });
  }

  String _formatTob(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDob(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _placeLine() {
    final parts = <String>[];
    final c = _city.text.trim();
    if (c.isNotEmpty) parts.add(c);
    if (_state != null && _state!.isNotEmpty) parts.add(_state!);
    if (_country != null && _country!.isNotEmpty) parts.add(_country!);
    return parts.join(', ');
  }

  Future<void> _saveToProfile() async {
    final result = _active;
    if (result == null) return;
    final cb = widget.onSaveToProfile;
    if (cb == null) return;
    setState(() => _saving = true);
    try {
      cb(HoroscopeSaveResult(
        star: result.star,
        rashi: result.rashi,
        lagnam: result.lagnam,
        method: _method,
        timeOfBirth: _tob != null ? _formatTob(_tob!) : '',
        placeOfBirth: _placeLine(),
        dobIso: _dob?.toIso8601String().split('T').first,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Dart equivalent of `handleSave()` in `dashboard/horoscope/page.tsx`:
  /// builds the full `horoscope_details` payload (including `manual_grid`
  /// and derived `dhosham`) and upserts via the shared repository.
  Future<void> _saveFullMemberHoroscope() async {
    final result = _active;
    final uid = _memberUserId ?? Supabase.instance.client.auth.currentUser?.id;
    if (result == null || uid == null) return;
    if (_memberSaving) return;
    setState(() => _memberSaving = true);

    final isAutoMode = !result.isManual;
    final manualGrid = <String, List<int>>{
      for (final entry in _manual.entries) entry.key: entry.value.toList()..sort(),
    };
    String? dhosham;
    final pp = result.papaPulligal;
    if (pp != null) {
      final parts = <String>[];
      if (pp.sevvaiDosham == 'தோஷம் உள்ளது') parts.add('செவ்வாய் தோஷம்');
      if (pp.rahuDosham == 'தோஷம் உள்ளது') parts.add('ராகு தோஷம்');
      dhosham = parts.isEmpty ? 'தோஷம் இல்லை' : parts.join(', ');
    }

    final payload = <String, dynamic>{
      'star': result.star,
      'zodiac_sign': result.rashi,
      'lagnam': result.lagnam,
      'time_of_birth': isAutoMode && _tob != null ? _formatTob(_tob!) : null,
      'place_of_birth': isAutoMode ? _placeLine() : 'Manual Entry',
      'birth_state': isAutoMode ? _state : null,
      'birth_country': isAutoMode ? _country : null,
      'manual_grid': manualGrid,
      'dhosham': dhosham,
    };

    try {
      await ProfileExtendedRepository.saveHoroscope(uid, payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${_method == 'vakkiyam' ? 'Vakkiyam' : 'Thirukanitham'} to your profile.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _memberSaving = false);
    }
  }

  Future<void> _downloadPdf() async {
    final result = _active;
    if (result == null) return;
    try {
      final pdfData = await _buildPdf(result);
      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (format) async => pdfData,
        name: 'Horoscope_${(_name.text.trim().isEmpty ? 'Unknown' : _name.text.trim())}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF generation failed: $e')),
      );
    }
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
          widget.memberMode ? 'My horoscope' : 'Generate horoscope',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: _brand,
            letterSpacing: -0.3,
          ),
        ),
        iconTheme: const IconThemeData(color: _brand),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _headerCard(),
          if (_memberLoading) ...[
            const SizedBox(height: 12),
            _memberLoadingBanner(),
          ],
          const SizedBox(height: 16),
          _modeToggle(),
          const SizedBox(height: 14),
          if (_mode == _EntryMode.auto) _autoForm(),
          if (_mode == _EntryMode.manual) _manualForm(),
          const SizedBox(height: 14),
          _generateButton(),
          const SizedBox(height: 18),
          if (_active != null) _resultSection(),
        ],
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: _brand.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _brand,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _brand.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vedic horoscope generator',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E1E1E),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Compute your Rasi & Navamsa charts and download as PDF.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B6B6B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memberLoadingBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Loading your saved birth details…',
              style: TextStyle(
                fontSize: 12,
                color: _brand.withValues(alpha: 0.85),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(child: _modeChip(_EntryMode.auto, 'Birth data', Icons.calendar_today_rounded)),
          Expanded(child: _modeChip(_EntryMode.manual, 'Manual entry', Icons.touch_app_rounded)),
        ],
      ),
    );
  }

  Widget _modeChip(_EntryMode m, String label, IconData icon) {
    final selected = _mode == m;
    return InkWell(
      onTap: () => setState(() => _mode = m),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? _brand : Colors.black54),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
                letterSpacing: 0.5,
                color: selected ? _brand : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _autoForm() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: _dec('Name (optional)', hint: 'Enter name'),
          ),
          const SizedBox(height: 10),
          _pickerRow(
            label: 'Date of Birth',
            value: _dob == null ? 'Select date' : _formatDob(_dob!),
            icon: Icons.calendar_today_rounded,
            onTap: _pickDob,
          ),
          const SizedBox(height: 10),
          _pickerRow(
            label: 'Time of Birth',
            value: _tob == null ? 'Select time' : _formatTob(_tob!),
            icon: Icons.access_time_rounded,
            onTap: _pickTob,
          ),
          const SizedBox(height: 10),
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) return _kHoroscopeQuickCities;
              return _kHoroscopeQuickCities.where((c) => c.toLowerCase().contains(textEditingValue.text.toLowerCase()));
            },
            onSelected: (String selection) => _city.text = selection,
            fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
              // Sync our outer controller with this inner one if needed, or just let it be.
              // Actually, best to use our _city controller directly. But Autocomplete requires its own.
              // Let's just listen to it.
              controller.text = _city.text;
              controller.addListener(() { _city.text = controller.text; });
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: _dec('Birth city', hint: 'Select or type a city'),
              );
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _state,
            decoration: _dec('Birth state / region'),
            items: [
              for (final s in kIndianStatesAndUTs)
                DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _state = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _country,
            decoration: _dec('Birth country'),
            items: [
              for (final c in kWorldCountries)
                DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _country = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _method,
            decoration: _dec('Calculation method'),
            items: const [
              DropdownMenuItem(value: 'thirukanitham', child: Text('Thirukanitham (Drik)')),
              DropdownMenuItem(value: 'vakkiyam', child: Text('Vakkiyam')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _method = v);
            },
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => setState(() => _showLatLon = !_showLatLon),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _showLatLon ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 18,
                    color: _brand,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showLatLon ? 'Hide coordinates' : 'Set coordinates (advanced)',
                    style: const TextStyle(
                      color: _brand,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showLatLon) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: _dec('Latitude', hint: '13.0827'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lon,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: _dec('Longitude', hint: '80.2707'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Defaults to Chennai (13.0827, 80.2707). Used as input to the '
              'sidereal Lagnam calculation.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black.withValues(alpha: 0.55),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _manualForm() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(Icons.touch_app_rounded, color: Color(0xFFA16207)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Grid editor',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFA16207),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Pick a planet below, then tap chart boxes to place it. Same '
                        'planet can sit in multiple houses if needed.',
                        style: TextStyle(fontSize: 11, color: Color(0xFFB45309), height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in astro.planets)
                ChoiceChip(
                  label: Text('${p.abbr} · ${p.tamil}'),
                  selected: _activeManualPlanet == p.abbr,
                  onSelected: (_) => setState(() => _activeManualPlanet = p.abbr),
                ),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1,
            child: SouthIndianChart(
              type: 'Rasi',
              title: 'Rasi (manual placement)',
              planetsByHouse: _planetsByHouseFromManual(),
              centerLines: const ['Tap a box to toggle the active planet'],
              editable: true,
              onTapHouse: (h) => _toggleManual(_activeManualPlanet, h),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _clearManual,
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Clear placements'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _generateButton() {
    final disabled = _generating;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: _brand,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: disabled ? null : _generate,
      icon: _generating
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.bolt_rounded),
      label: Text(
        _generating
            ? 'Calculating…'
            : _mode == _EntryMode.auto
                ? 'Generate charts'
                : 'Preview grid',
        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
    );
  }

  Widget _resultSection() {
    final r = _active!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'thirukanitham', label: Text('Thirukanitham')),
                    ButtonSegment(value: 'vakkiyam', label: Text('Vakkiyam')),
                  ],
                  selected: {_method},
                  onSelectionChanged: (s) {
                    if (s.isEmpty) return;
                    setState(() => _method = s.first);
                  },
                  showSelectedIcon: false,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            if (widget.memberMode)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _brand,
                  foregroundColor: Colors.white,
                ),
                onPressed: _memberSaving ? null : _saveFullMemberHoroscope,
                icon: _memberSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_upload_rounded, size: 18),
                label: Text(
                  _memberSaving
                      ? 'Saving…'
                      : 'Save ${_method == 'vakkiyam' ? 'Vakkiyam' : 'Thirukanitham'} to Profile',
                ),
              )
            else if (widget.allowSaveToProfile && widget.onSaveToProfile != null && !r.isManual)
              FilledButton.tonalIcon(
                onPressed: _saving ? null : _saveToProfile,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt_rounded, size: 18),
                label: const Text('Save star / rasi / lagnam'),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
              ),
              onPressed: _downloadPdf,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Download PDF'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _summaryCard(r),
        const SizedBox(height: 14),
        _chartsRow(r),
        const SizedBox(height: 18),
        _panchangCard(r),
        const SizedBox(height: 14),
        if (r.papaPulligal != null) _papaPulligalCard(r),
        const SizedBox(height: 14),
        if (r.dasaPeriods.isNotEmpty) _dasaCard(r),
        const SizedBox(height: 14),
        _planetsTableCard(r),
      ],
    );
  }

  Widget _summaryCard(astro.HoroscopeDetails r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_name.text.trim().isNotEmpty)
            Text(
              'Horoscope of ${_name.text.trim()}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(0xFF1E1E1E),
              ),
            ),
          const SizedBox(height: 6),
          if (_dob != null) _summaryKv('Date of birth', _formatDob(_dob!)),
          if (_tob != null) _summaryKv('Time of birth', _formatTob(_tob!)),
          if (_placeLine().isNotEmpty) _summaryKv('Place of birth', _placeLine()),
          _summaryKv('Method', r.calculationMethod == 'vakkiyam' ? 'Vakkiyam' : 'Thirukanitham (Lahiri)'),
          if (!r.isManual) ...[
            _summaryKv('Nakshatra', r.star),
            _summaryKv('Rasi', r.rashi),
            _summaryKv('Lagnam', r.lagnam),
            _summaryKv('Yoga', r.yoga),
          ],
        ],
      ),
    );
  }

  Widget _summaryKv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF1E1E1E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartsRow(astro.HoroscopeDetails r) {
    Map<int, List<String>> rasiHouses;
    if (r.isManual) {
      rasiHouses = _planetsByHouseFromManual();
    } else {
      rasiHouses = _planetsByHouseFromResult(r, false);
    }
    final navHouses = r.isManual ? <int, List<String>>{} : _planetsByHouseFromResult(r, true);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final chartWidth = wide ? (constraints.maxWidth - 16) / 2 : constraints.maxWidth;
        final rasi = SizedBox(
          width: chartWidth,
          child: SouthIndianChart(
            type: 'Rasi',
            title: 'ராசி (பிறந்த அட்டவணை)',
            planetsByHouse: rasiHouses,
            centerLines: [
              if (r.star.isNotEmpty) r.star,
              if (_dob != null) _formatDob(_dob!),
              if (_tob != null) _formatTob(_tob!),
            ],
            editable: r.isManual,
            onTapHouse: r.isManual ? (h) => _toggleManual(_activeManualPlanet, h) : null,
          ),
        );
        final nav = SizedBox(
          width: chartWidth,
          child: SouthIndianChart(
            type: 'Navamsam',
            title: 'நவாம்சம்',
            planetsByHouse: navHouses,
          ),
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [rasi, const SizedBox(width: 16), nav],
          );
        }
        return Column(children: [rasi, const SizedBox(height: 16), nav]);
      },
    );
  }

  Widget _panchangCard(astro.HoroscopeDetails r) {
    if (r.isManual) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        ),
        child: const Text(
          'Manual chart — switch to Birth data mode to compute Panchang, '
          'Dasa periods and Papa Pulligal automatically.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF6B6B6B), height: 1.4),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Panchang'),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _summaryKv('Nakshatra', astro.nakshatras[r.nakshatraIndex]),
              _summaryKv('Tithi #', '${r.tithiIndex + 1}'),
              _summaryKv('Yoga', r.yoga),
              _summaryKv('Sunrise', r.sunrise),
              _summaryKv('Sunset', r.sunset),
            ],
          ),
        ],
      ),
    );
  }

  Widget _papaPulligalCard(astro.HoroscopeDetails r) {
    final pp = r.papaPulligal!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
            ),
            child: const Text(
              'பாப புள்ளிகள் · Papa Pulligal',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 28,
              dataRowMaxHeight: 36,
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('கிரகம்', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11))),
                DataColumn(label: Text('Lagna #'), numeric: true),
                DataColumn(label: Text('L pts'), numeric: true),
                DataColumn(label: Text('Moon #'), numeric: true),
                DataColumn(label: Text('M pts'), numeric: true),
                DataColumn(label: Text('Venus #'), numeric: true),
                DataColumn(label: Text('V pts'), numeric: true),
              ],
              rows: [
                for (final row in pp.rows)
                  DataRow(cells: [
                    DataCell(Text(row.planet)),
                    DataCell(Text('${row.v1}')),
                    DataCell(Text(row.p1)),
                    DataCell(Text('${row.v2}')),
                    DataCell(Text(row.p2)),
                    DataCell(Text('${row.v3}')),
                    DataCell(Text(row.p3)),
                  ]),
                DataRow(cells: [
                  const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w900))),
                  const DataCell(Text('')),
                  DataCell(Text(pp.totalP1, style: const TextStyle(fontWeight: FontWeight.w900))),
                  const DataCell(Text('')),
                  DataCell(Text(pp.totalP2, style: const TextStyle(fontWeight: FontWeight.w900))),
                  const DataCell(Text('')),
                  DataCell(Text(pp.totalP3, style: const TextStyle(fontWeight: FontWeight.w900))),
                ]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sevvai dosham: ${pp.sevvaiDosham}'),
                Text('Rahu dosham: ${pp.rahuDosham}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dasaCard(astro.HoroscopeDetails r) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
            ),
            child: const Text(
              'விம்சோத்தரி தசை · Vimshottari Dasa',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 28,
              dataRowMaxHeight: 36,
              columnSpacing: 28,
              columns: const [
                DataColumn(label: Text('Dasa-Bhukti')),
                DataColumn(label: Text('Start')),
                DataColumn(label: Text('End')),
              ],
              rows: [
                for (final p in r.dasaPeriods)
                  DataRow(cells: [
                    DataCell(Text('${p.dasa}-${p.bhukti}')),
                    DataCell(Text(p.start)),
                    DataCell(Text(p.end)),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planetsTableCard(astro.HoroscopeDetails r) {
    if (r.planets.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FC),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
            ),
            child: const Text(
              'நிராயண ஸ்புடங்கள் · Sputams',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8),
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 28,
              dataRowMaxHeight: 36,
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('Planet')),
                DataColumn(label: Text('Longitude')),
                DataColumn(label: Text('Rasi')),
                DataColumn(label: Text('Rasi Sputam')),
                DataColumn(label: Text('Pada'), numeric: true),
              ],
              rows: [
                for (final p in r.planets)
                  DataRow(cells: [
                    DataCell(Text(astro.planetTamilFull(p))),
                    DataCell(Text(astro.formatSputam(p.longitude))),
                    DataCell(Text(astro.rasiNamesTamil[p.rasiIndex])),
                    DataCell(Text(astro.formatSputam(p.siderealLongitude))),
                    DataCell(Text('${p.navamsamIndex % 4 + 1}')),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        t.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
          color: _brand.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  Widget _pickerRow({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _dec(label).copyWith(suffixIcon: Icon(icon, size: 18)),
        child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
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

  // ---------- PDF generation (Printing + pdf packages) ----------------------

  Future<Uint8List> _buildPdf(astro.HoroscopeDetails r) async {
    final doc = pw.Document();
    final name = _name.text.trim().isEmpty ? 'User' : _name.text.trim();
    final tamilFont = await PdfGoogleFonts.notoSansTamilBold();
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    pw.TextStyle ts(double sz, {bool bold = false}) => pw.TextStyle(
          fontSize: sz,
          font: bold ? boldFont : regularFont,
          fontFallback: [tamilFont],
        );

    pw.Widget kv(String k, String v) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 110,
              child: pw.Text(k, style: ts(9, bold: true)),
            ),
            pw.Expanded(child: pw.Text(v, style: ts(9))),
          ],
        ),
      );
    }

    pw.Widget chart(String title, Map<int, List<String>> houses, {List<String> center = const []}) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            color: pw_color.PdfColor.fromInt(0xFFEEF2FF),
            padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: pw.Text(title, style: ts(9, bold: true)),
          ),
          pw.SizedBox(height: 2),
          pw.Container(
            width: 160,
            height: 160,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: pw_color.PdfColor.fromInt(0xFF7E22CE), width: 1.0),
            ),
            child: pw.Stack(
              children: [
                ...List.generate(16, (i) {
                  final row = i ~/ 4;
                  final col = i % 4;
                  final grid = [
                    [11, 0, 1, 2],
                    [10, -1, -1, 3],
                    [9, -1, -1, 4],
                    [8, 7, 6, 5],
                  ];
                  final rasi = grid[row][col];
                  if (rasi == -1) return pw.SizedBox();
                  final occ = houses[rasi] ?? const <String>[];
                  return pw.Positioned(
                    left: col * 40.0,
                    top: row * 40.0,
                    child: pw.SizedBox(
                      width: 40.0,
                      height: 40.0,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(2),
                        child: pw.Stack(
                        children: [
                          pw.Positioned(
                            left: 1,
                            top: 1,
                            child: pw.Text(
                              astro.rasiNamesTamil[rasi],
                              style: pw.TextStyle(
                                fontSize: 5,
                                color: pw_color.PdfColor.fromInt(0xFF6B7280),
                                font: regularFont,
                                fontFallback: [tamilFont],
                              ),
                            ),
                          ),
                          pw.Align(
                            alignment: pw.Alignment.center,
                            child: pw.Wrap(
                              spacing: 1,
                              runSpacing: 1,
                              alignment: pw.WrapAlignment.center,
                              children: [
                                for (final a in occ)
                                  pw.Text(
                                    a,
                                    style: pw.TextStyle(
                                      fontSize: 7,
                                      color: pw_color.PdfColor.fromInt(0xFF1F2937),
                                      font: boldFont,
                                      fontFallback: [tamilFont],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    ),
                  );
                }),
                pw.Positioned(left: 40, top: 0, child: pw.SizedBox(width: 1, height: 160, child: pw.Container(color: pw_color.PdfColor.fromInt(0xFF7E22CE)))),
                pw.Positioned(left: 80, top: 0, child: pw.SizedBox(width: 1, height: 40, child: pw.Container(color: pw_color.PdfColor.fromInt(0xFF7E22CE)))),
                pw.Positioned(left: 80, top: 120, child: pw.SizedBox(width: 1, height: 40, child: pw.Container(color: pw_color.PdfColor.fromInt(0xFF7E22CE)))),
                pw.Positioned(left: 120, top: 0, child: pw.SizedBox(width: 1, height: 160, child: pw.Container(color: pw_color.PdfColor.fromInt(0xFF7E22CE)))),
                pw.Positioned(left: 0, top: 40, child: pw.SizedBox(width: 160, height: 1, child: pw.Container(color: pw_color.PdfColor.fromInt(0xFF7E22CE)))),
                pw.Positioned(left: 0, top: 80, child: pw.SizedBox(width: 40, height: 1, child: pw.Container(color: pw_color.PdfColor.fromInt(0xFF7E22CE)))),
                pw.Positioned(left: 120, top: 80, child: pw.SizedBox(width: 40, height: 1, child: pw.Container(color: pw_color.PdfColor.fromInt(0xFF7E22CE)))),
                pw.Positioned(left: 0, top: 120, child: pw.SizedBox(width: 160, height: 1, child: pw.Container(color: pw_color.PdfColor.fromInt(0xFF7E22CE)))),
                pw.Positioned(
                  left: 40,
                  top: 40,
                  child: pw.SizedBox(
                    width: 80,
                    height: 80,
                    child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      for (final l in center)
                        pw.Text(l, textAlign: pw.TextAlign.center, style: ts(7)),
                    ],
                  ),
                ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final rasiHouses = r.isManual
        ? _planetsByHouseFromManual()
        : _planetsByHouseFromResult(r, false);
    final navHouses = r.isManual ? <int, List<String>>{} : _planetsByHouseFromResult(r, true);

    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          pw.Center(child: pw.Text('Horoscope of $name', style: ts(16, bold: true))),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              r.calculationMethod == 'vakkiyam' ? 'Vakkiyam' : 'Thirukanitham (Lahiri)',
              style: ts(9),
            ),
          ),
          pw.SizedBox(height: 12),
          if (_dob != null) kv('Date of birth', _formatDob(_dob!)),
          if (_tob != null) kv('Time of birth', _formatTob(_tob!)),
          if (_placeLine().isNotEmpty) kv('Place of birth', _placeLine()),
          if (!r.isManual) ...[
            kv('Nakshatra', r.star),
            kv('Rasi', r.rashi),
            kv('Lagnam', r.lagnam),
            kv('Yoga', r.yoga),
          ],
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: chart('ராசி (Rasi)', rasiHouses,
                    center: [
                      if (r.star.isNotEmpty) r.star,
                      if (_dob != null) _formatDob(_dob!),
                      if (_tob != null) _formatTob(_tob!),
                    ]),
              ),
              pw.SizedBox(width: 16),
              pw.Expanded(child: chart('நவாம்சம் (Navamsam)', navHouses)),
            ],
          ),
          if (!r.isManual && r.papaPulligal != null) ...[
            pw.SizedBox(height: 14),
            pw.Text('Papa Pulligal', style: ts(10, bold: true)),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              cellStyle: ts(8),
              headerStyle: ts(8, bold: true),
              border: pw.TableBorder.all(width: 0.4),
              data: [
                ['Planet', 'L#', 'Lpt', 'M#', 'Mpt', 'V#', 'Vpt'],
                for (final row in r.papaPulligal!.rows)
                  [
                    row.planet,
                    '${row.v1}', row.p1,
                    '${row.v2}', row.p2,
                    '${row.v3}', row.p3,
                  ],
                ['Total', '', r.papaPulligal!.totalP1, '', r.papaPulligal!.totalP2, '', r.papaPulligal!.totalP3],
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text('Sevvai dosham: ${r.papaPulligal!.sevvaiDosham}', style: ts(8)),
            pw.Text('Rahu dosham: ${r.papaPulligal!.rahuDosham}', style: ts(8)),
          ],
          if (!r.isManual && r.dasaPeriods.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            pw.Text('Vimshottari Dasa', style: ts(10, bold: true)),
            pw.SizedBox(height: 4),
            pw.TableHelper.fromTextArray(
              cellStyle: ts(7),
              headerStyle: ts(8, bold: true),
              border: pw.TableBorder.all(width: 0.3),
              data: [
                ['Dasa-Bhukti', 'Start', 'End'],
                for (final p in r.dasaPeriods.take(40))
                  ['${p.dasa}-${p.bhukti}', p.start, p.end],
              ],
            ),
          ],
          pw.SizedBox(height: 18),
          pw.Center(
            child: pw.Text(
              '© Manavizha · ${r.calculationMethod == 'vakkiyam' ? 'Vakkiyam' : 'Thirukanitham'}',
              style: ts(7),
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }
}

/// Optional helper for callers that want to push the screen directly. When
/// the user taps **Save** in the result toolbar, the dialog is popped with
/// the captured [HoroscopeSaveResult] so the caller can write the values
/// back into `horoscope_details`.
Future<HoroscopeSaveResult?> openHoroscope(
  BuildContext context, {
  String? name,
  DateTime? dob,
  TimeOfDay? tob,
  String? city,
  String? state,
  String? country,
  bool allowSaveToProfile = false,
}) async {
  HoroscopeSaveResult? captured;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (innerCtx) => HoroscopeScreen(
        initialName: name,
        initialDob: dob,
        initialTob: tob,
        initialCity: city,
        initialState: state,
        initialCountry: country,
        allowSaveToProfile: allowSaveToProfile,
        onSaveToProfile: allowSaveToProfile
            ? (r) {
                captured = r;
                Navigator.of(innerCtx).pop();
              }
            : null,
      ),
    ),
  );
  return captured;
}
