import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Flutter port of `manavizha/components/partner-preferences-form.tsx`
/// (web route `/dashboard/preferences`).
///
/// Reads and upserts the `partner_preferences` row directly — same as the web,
/// which has no API route for preferences. Select options come from the same
/// `master_*` tables the web loads via `useMasterData`, with the web's static
/// fallbacks when a table is empty or unreadable.
class PartnerPreferencesScreen extends StatefulWidget {
  const PartnerPreferencesScreen({super.key});

  @override
  State<PartnerPreferencesScreen> createState() =>
      _PartnerPreferencesScreenState();
}

class _PartnerPreferencesScreenState extends State<PartnerPreferencesScreen> {
  static const Color _brand = Color(0xFF2FA086);

  // ── Static option lists (mirrors web partner-preferences-form.tsx) ───────
  static const List<String> _countries = ['Any', 'India', 'USA', 'UK', 'Canada', 'Australia', 'Singapore', 'UAE', 'Kuwait', 'Qatar', 'Malaysia', 'Germany', 'France', 'Italy', 'Sri Lanka', 'New Zealand', 'Others'];
  static const List<String> _states = ['Any', 'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chandigarh', 'Chhattisgarh', 'Delhi', 'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jammu & Kashmir', 'Jharkhand', 'Karnataka', 'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha', 'Puducherry', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal', 'International / Abroad'];
  static const List<String> _cities = ['Any', 'Chennai', 'Coimbatore', 'Madurai', 'Tiruchirappalli', 'Salem', 'Tirunelveli', 'Vellore', 'Erode', 'Tiruppur', 'Thoothukkudi', 'Kancheepuram', 'Bangalore', 'Mumbai', 'Delhi', 'Hyderabad', 'Kolkata', 'Pune', 'Ahmedabad', 'Surat', 'Kochi', 'Vishakhapatnam', 'Jaipur', 'Lucknow', 'Singapore', 'Dubai', 'London', 'Others'];
  static const List<String> _religionsFallback = ['Any', 'Hindu', 'Christian', 'Muslim', 'Jain', 'Sikh', 'Buddhist', 'Others'];
  static const List<String> _indianLanguages = ['Tamil', 'Telugu', 'Kannada', 'Malayalam', 'Hindi', 'Marathi', 'Gujarati', 'Bengali', 'Punjabi', 'Urdu', 'Assamese', 'Bodo', 'Dogri', 'Kashmiri', 'Konkani', 'Maithili', 'Manipuri', 'Nepali', 'Odia', 'Sanskrit', 'Santali', 'Sindhi', 'Tulu', 'Kodava', 'Rajasthani', 'Bhojpuri', 'Haryanvi', 'Magahi', 'Marwari', 'Chhattisgarhi', 'Kutchi', 'Sourashtra', 'Beary', 'Gondi', 'Mundari', 'Rabha', 'Misings', 'Karbi'];
  static const List<String> _stars = ['Any', 'Ashwini', 'Bharani', 'Krittika', 'Rohini', 'Mrigashira', 'Ardra', 'Punarvasu', 'Pushya', 'Ashlesha', 'Magha', 'Purva Phalguni', 'Uttara Phalguni', 'Hasta', 'Chitra', 'Swati', 'Vishakha', 'Anuradha', 'Jyeshtha', 'Mula', 'Purva Ashadha', 'Uttara Ashadha', 'Shravana', 'Dhanishtha', 'Shatabhisha', 'Purva Bhadrapada', 'Uttara Bhadrapada', 'Revati'];
  static const List<String> _raasi = ['Any', 'Mesham (Aries)', 'Rishabam (Taurus)', 'Mithunam (Gemini)', 'Katakam (Cancer)', 'Simmam (Leo)', 'Kanni (Virgo)', 'Tulam (Libra)', 'Viruchigam (Scorpio)', 'Dhanusu (Sagittarius)', 'Makaram (Capricorn)', 'Kumbam (Aquarius)', 'Meenam (Pisces)'];
  static const List<String> _incomeOptions = ['Any', 'Less than Rs.50 thousand', 'Rs.50 thousand', 'Rs.1 Lakh', 'Rs.2 Lakhs', 'Rs.3 Lakhs', 'Rs.4 Lakhs', 'Rs.5 Lakhs', 'Rs.6 Lakhs', 'Rs.7 Lakhs', 'Rs.8 Lakhs', 'Rs.9 Lakhs', 'Rs.10 Lakhs', 'Rs.11 Lakhs', 'Rs.12 Lakhs', 'Rs.13 Lakhs', 'Rs.14 Lakhs', 'Rs.15 Lakhs', 'Rs.20 Lakhs', 'Rs.25 Lakhs', 'Rs.30 Lakhs', 'Rs.35 Lakhs', 'Rs.40 Lakhs', 'Rs.45 Lakhs', 'Rs.50 Lakhs', 'Rs.60 Lakhs', 'Rs.70 Lakhs', 'Rs.80 Lakhs', 'Rs.90 Lakhs', 'Rs.1 Crore', 'Rs.1 Crore & Above'];
  static const List<String> _employmentTypes = ['Private', 'Government/PSU', 'Business', 'Defence', 'Self Employed', 'Student', 'Not Working'];
  static const List<String> _occupations = ['Administration', 'Agriculture', 'Airline', 'Architecture & design', 'Banking & finance', 'Beauty & fashion', 'Bpo & customer service', 'Civil services', 'Corporate professionals', 'Defence', 'Doctor', 'Education & training', 'Engineering', 'Hospitality', 'It & software', 'Legal', 'Media & entertainment', 'Medical & healthcare-others', 'Merchant navy', 'Police / law enforcement', 'Scientist', 'Senior management', 'Other'];
  static const List<String> _educationLevelsFallback = ["Bachelor's - Engineering / Computer Science", "Master's - Engineering / Computer Science", "Bachelor's - Arts / Science / Commerce", "Master's - Arts / Science / Commerce", "Bachelor's - Management", "Master's - Management", "Bachelor's - Medicine - General / Dental / Surgeon", "Master's - Medicine - General / Dental / Surgeon", "Bachelor's - Pharmacy / Nursing or Health Sciences", "Master's - Pharmacy / Nursing or Health Sciences", "Bachelor's - Legal", "Master's - Legal", 'Finance - ICWAI / CA / CS / CFA', 'Civil Services', 'Doctorates', 'Diploma / Polytechnic', 'Higher Secondary / Secondary'];
  static const List<String> _branches = ['Any', 'Computer Science', 'Engineering', 'Commerce', 'Arts', 'Science', 'Medicine', 'Management', 'Law', 'Finance', 'Others'];

  List<String> get _motherTongues => ['Any', ..._indianLanguages, 'English', 'Others'];

  bool _loading = true;
  bool _saving = false;
  String? _userId;

  // ── Form state (names mirror the web `fd` object) ────────────────────────
  final _ageMinCtrl = TextEditingController();
  final _ageMaxCtrl = TextEditingController();
  final _heightMinCtrl = TextEditingController();
  final _heightMaxCtrl = TextEditingController();
  String _maritalStatus = '';
  List<String> _languages = [];
  String _physicalStatus = '';
  String _eatingHabits = '';
  String _smokingHabits = '';
  String _drinkingHabits = '';
  String _religion = '';
  String _caste = '';
  String _subcaste = '';
  bool _casteCompulsory = false;
  String _star = '';
  String _raasiValue = '';
  String _dosham = '';
  List<String> _education = [];
  List<String> _degrees = [];
  List<String> _branchesSel = [];
  List<String> _employedIn = [];
  List<String> _occupation = [];
  String _incomeMin = '';
  String _country = '';
  String _state = '';
  String _city = '';

  /// Whether the loaded row contained `caste_compulsory` — the column is not
  /// written by the web form, so only persist it when it exists in the schema.
  bool _casteCompulsoryColumnExists = false;

  // Master data (value + optional category), loaded with fallbacks.
  List<String> _casteOptions = const ['Any'];
  List<Map<String, String?>> _subcasteRows = const [];
  List<String> _maritalOptions = const ['Any'];
  List<String> _foodOptions = const ['Any'];
  List<String> _religionOptions = _religionsFallback;
  List<Map<String, String?>> _educationLevelRows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ageMinCtrl.dispose();
    _ageMaxCtrl.dispose();
    _heightMinCtrl.dispose();
    _heightMaxCtrl.dispose();
    super.dispose();
  }

  // ── Loading ──────────────────────────────────────────────────────────────

  Future<List<Map<String, String?>>> _masterRows(
      SupabaseClient c, String table) async {
    try {
      final rows = await c.from(table).select('value, category');
      return [
        for (final r in (rows as List<dynamic>))
          {
            'value': (r as Map)['value']?.toString(),
            'category': r['category']?.toString(),
          }
      ];
    } catch (_) {
      return const [];
    }
  }

  List<String> _masterValues(List<Map<String, String?>> rows,
      {required List<String> fallback}) {
    final values = rows
        .map((r) => r['value']?.trim() ?? '')
        .where((v) => v.isNotEmpty)
        .toList();
    if (values.isEmpty) return fallback;
    return ['Any', ...values];
  }

  Future<void> _load() async {
    final c = Supabase.instance.client;
    final uid = c.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _userId = uid;

    try {
      final results = await Future.wait<dynamic>([
        c.from('partner_preferences').select().eq('user_id', uid).maybeSingle(),
        c.from('personal_details').select().eq('user_id', uid).maybeSingle(),
        c.from('horoscope_details').select().eq('user_id', uid).maybeSingle(),
        c
            .from('education_details')
            .select()
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        _masterRows(c, 'master_caste'),
        _masterRows(c, 'master_subcaste'),
        _masterRows(c, 'master_marital_status'),
        _masterRows(c, 'master_food_preferences'),
        _masterRows(c, 'master_religion'),
        _masterRows(c, 'master_education_level'),
      ]);

      final pref = results[0] == null
          ? null
          : Map<String, dynamic>.from(results[0] as Map);
      final profile = results[1] == null
          ? null
          : Map<String, dynamic>.from(results[1] as Map);
      final horoscope = results[2] == null
          ? null
          : Map<String, dynamic>.from(results[2] as Map);
      final education = results[3] == null
          ? null
          : Map<String, dynamic>.from(results[3] as Map);

      _casteOptions = _masterValues(
          results[4] as List<Map<String, String?>>,
          fallback: const ['Any']);
      _subcasteRows = results[5] as List<Map<String, String?>>;
      _maritalOptions = _masterValues(
          results[6] as List<Map<String, String?>>,
          fallback: const ['Any', 'Never Married', 'Divorced', 'Widowed', 'Awaiting Divorce']);
      _foodOptions = _masterValues(
          results[7] as List<Map<String, String?>>,
          fallback: const ['Any', 'Vegetarian', 'Non-Vegetarian', 'Eggetarian']);
      _religionOptions = _masterValues(
          results[8] as List<Map<String, String?>>,
          fallback: _religionsFallback);
      _educationLevelRows = results[9] as List<Map<String, String?>>;

      String str(dynamic v) => v?.toString().trim() ?? '';
      List<String> strList(dynamic v) => v is List
          ? v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList()
          : (str(v).isNotEmpty ? [str(v)] : <String>[]);
      String firstOf(dynamic v) {
        final l = strList(v);
        return l.isEmpty ? '' : l.first;
      }

      if (pref != null) {
        _casteCompulsoryColumnExists = pref.containsKey('caste_compulsory');
        _ageMinCtrl.text = str(pref['preferred_age_min']);
        _ageMaxCtrl.text = str(pref['preferred_age_max']);
        _heightMinCtrl.text = str(pref['preferred_height_min']);
        _heightMaxCtrl.text = str(pref['preferred_height_max']);
        _maritalStatus = firstOf(pref['preferred_marital_status']);
        _languages = strList(pref['preferred_languages']);
        _physicalStatus = str(pref['preferred_physical_status']);
        _eatingHabits = firstOf(pref['preferred_eating_habits']);
        _smokingHabits = firstOf(pref['preferred_smoking_habits']);
        _drinkingHabits = firstOf(pref['preferred_drinking_habits']);
        _religion = str(pref['preferred_religion']);
        _caste = str(pref['preferred_caste']);
        _subcaste = str(pref['preferred_subcaste']);
        _casteCompulsory = pref['caste_compulsory'] == true;
        _star = str(pref['preferred_star']);
        _raasiValue = str(pref['preferred_raasi']);
        _dosham = str(pref['preferred_dosham']);
        _education = strList(pref['preferred_education']);
        _degrees = strList(pref['preferred_degrees']);
        _branchesSel = strList(pref['preferred_branches']);
        _employedIn = strList(pref['preferred_employed_in']);
        _occupation = strList(pref['preferred_occupation']);
        _incomeMin = str(pref['preferred_annual_income_min']);
        _country = str(pref['preferred_country']);
        _state = str(pref['preferred_state']);
        _city = str(pref['preferred_city']);
      } else if (profile != null) {
        // Smart defaults from the member's own profile — same as web.
        final userAge = int.tryParse(str(profile['age'])) ?? 25;
        final userHeight = int.tryParse(str(profile['height'])) ?? 165;
        _ageMinCtrl.text = (userAge - 5).clamp(18, 100).toString();
        _ageMaxCtrl.text = (userAge + 5).toString();
        _heightMinCtrl.text = (userHeight - 15).clamp(120, 250).toString();
        _heightMaxCtrl.text = (userHeight + 15).toString();
        _maritalStatus = str(profile['marital_status']).isNotEmpty
            ? str(profile['marital_status'])
            : 'Never Married';
        _religion = str(profile['religion']);
        _caste = str(profile['caste']);
        _subcaste =
            str(profile['subcaste']).isNotEmpty ? str(profile['subcaste']) : 'Any';
        _eatingHabits = str(profile['food_preference']).isNotEmpty
            ? str(profile['food_preference'])
            : 'Any';
        _languages = strList(profile['languages']);
        _star = str(horoscope?['star']).isNotEmpty ? str(horoscope?['star']) : 'Any';
        _raasiValue = str(horoscope?['zodiac_sign']).isNotEmpty
            ? str(horoscope?['zodiac_sign'])
            : 'Any';
        _dosham = str(horoscope?['dhosham']).isNotEmpty
            ? str(horoscope?['dhosham'])
            : 'Any';
        final edu = str(education?['education']);
        if (edu.isNotEmpty) _education = [edu];
      }
    } catch (e) {
      debugPrint('PartnerPreferences load: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Derived options ──────────────────────────────────────────────────────

  List<String> get _filteredSubcastes {
    if (_caste.isEmpty || _caste == 'Any') return const ['Any'];
    final filtered = _subcasteRows
        .where((s) {
          final cat = s['category']?.trim() ?? '';
          return cat.isEmpty || cat == _caste;
        })
        .map((s) => s['value']?.trim() ?? '')
        .where((v) => v.isNotEmpty)
        .toList();
    return ['Any', ...filtered];
  }

  List<String> get _educationLevelOptions {
    final cats = _educationLevelRows
        .map((r) => r['category']?.trim() ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return cats.isEmpty ? _educationLevelsFallback : cats;
  }

  List<String> get _degreeOptions {
    var rows = _educationLevelRows;
    if (_education.isNotEmpty && !_education.contains('Any')) {
      rows = rows
          .where((r) => _education.contains(r['category']?.trim() ?? ''))
          .toList();
    }
    final vals = rows
        .map((r) => r['value']?.trim() ?? '')
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return vals;
  }

  // ── Saving ───────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final uid = _userId;
    if (uid == null) return;
    setState(() => _saving = true);

    int? asInt(String s) => s.trim().isEmpty ? null : int.tryParse(s.trim());
    String? orNull(String s) => s.trim().isEmpty ? null : s.trim();
    List<String> orAny(String s) => s.trim().isEmpty ? ['Any'] : [s.trim()];

    final row = <String, dynamic>{
      'user_id': uid,
      'preferred_age_min': asInt(_ageMinCtrl.text),
      'preferred_age_max': asInt(_ageMaxCtrl.text),
      'preferred_height_min': asInt(_heightMinCtrl.text),
      'preferred_height_max': asInt(_heightMaxCtrl.text),
      'preferred_marital_status': orAny(_maritalStatus),
      'preferred_languages': _languages,
      'preferred_physical_status': orNull(_physicalStatus),
      'preferred_eating_habits': orAny(_eatingHabits),
      'preferred_smoking_habits': orAny(_smokingHabits),
      'preferred_drinking_habits': orAny(_drinkingHabits),
      'preferred_religion': orNull(_religion),
      'preferred_caste': orNull(_caste),
      'preferred_subcaste': orNull(_subcaste),
      'preferred_star': orNull(_star),
      'preferred_raasi': orNull(_raasiValue),
      'preferred_dosham': orNull(_dosham),
      'preferred_education': _education,
      'preferred_degrees': _degrees,
      'preferred_branches': _branchesSel,
      'preferred_employed_in': _employedIn,
      'preferred_occupation': _occupation,
      'preferred_annual_income_min': orNull(_incomeMin),
      'preferred_country': orNull(_country),
      'preferred_state': orNull(_state),
      'preferred_city': orNull(_city),
      if (_casteCompulsoryColumnExists) 'caste_compulsory': _casteCompulsory,
    };

    try {
      await Supabase.instance.client
          .from('partner_preferences')
          .upsert(row, onConflict: 'user_id');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Partner preferences saved successfully!')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('PartnerPreferences save: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save. Please try again.')),
      );
    }
  }

  // ── Pickers ──────────────────────────────────────────────────────────────

  Future<void> _pickSingle({
    required String title,
    required List<String> options,
    required String current,
    required ValueChanged<String> onPicked,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final opt in options)
                      ListTile(
                        dense: true,
                        title: Text(opt),
                        trailing: (current.isEmpty ? 'Any' : current) == opt
                            ? const Icon(Icons.check_rounded, color: _brand)
                            : null,
                        onTap: () => Navigator.pop(ctx, opt),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      // 'Any' is stored as empty — same convention as the web form.
      onPicked(picked == 'Any' ? '' : picked);
    }
  }

  Future<void> _pickMulti({
    required String title,
    required List<String> options,
    required List<String> current,
    required ValueChanged<List<String>> onPicked,
  }) async {
    final selected = current.where((s) => s != 'Any').toSet();
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w900)),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(ctx, selected.toList()),
                        child: const Text('Done',
                            style: TextStyle(
                                color: _brand, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      CheckboxListTile(
                        dense: true,
                        activeColor: _brand,
                        title: const Text('Any'),
                        value: selected.isEmpty,
                        onChanged: (_) =>
                            setSheetState(() => selected.clear()),
                      ),
                      for (final opt in options.where((o) => o != 'Any'))
                        CheckboxListTile(
                          dense: true,
                          activeColor: _brand,
                          title: Text(opt),
                          value: selected.contains(opt),
                          onChanged: (v) => setSheetState(() {
                            if (v == true) {
                              selected.add(opt);
                            } else {
                              selected.remove(opt);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null) onPicked(picked);
  }

  // ── UI helpers ───────────────────────────────────────────────────────────

  Widget _sectionCard(
      {required IconData icon,
      required String title,
      required String subtitle,
      required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _brand.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: _brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w900)),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.black.withValues(alpha: 0.5))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _selectTile(String label, String value, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: const Color(0xFFF5F6FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
          child: Text(
            value.isEmpty ? 'Any' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _multiTile(
      String label, List<String> values, VoidCallback onTap) {
    final display = values.where((v) => v != 'Any').toList();
    return _selectTile(
        label, display.isEmpty ? '' : display.join(', '), onTap);
  }

  Widget _rangeRow(String label, TextEditingController minCtrl,
      TextEditingController maxCtrl) {
    InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFFF5F6FA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.6))),
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: minCtrl,
                  keyboardType: TextInputType.number,
                  decoration: deco('Min'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('to'),
              ),
              Expanded(
                child: TextField(
                  controller: maxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: deco('Max'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Partner Preferences',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _brand))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 14),
                  child: Text(
                    'Set your criteria — we use this to find your best matches.',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.black.withValues(alpha: 0.55)),
                  ),
                ),
                _sectionCard(
                  icon: Icons.tune_rounded,
                  title: 'Basic & lifestyle preferences',
                  subtitle: 'Age, height, marital status, and lifestyle habits',
                  children: [
                    _rangeRow('Age range', _ageMinCtrl, _ageMaxCtrl),
                    _rangeRow('Height range (cm)', _heightMinCtrl, _heightMaxCtrl),
                    _selectTile('Marital Status', _maritalStatus, () =>
                        _pickSingle(
                            title: 'Marital Status',
                            options: _maritalOptions,
                            current: _maritalStatus,
                            onPicked: (v) => setState(() => _maritalStatus = v))),
                    _selectTile('Physical Status', _physicalStatus, () =>
                        _pickSingle(
                            title: 'Physical Status',
                            options: const ['Any', 'Normal', 'Physically Challenged'],
                            current: _physicalStatus,
                            onPicked: (v) => setState(() => _physicalStatus = v))),
                    _multiTile('Preferred Languages', _languages, () =>
                        _pickMulti(
                            title: 'Preferred Languages',
                            options: _motherTongues,
                            current: _languages,
                            onPicked: (v) => setState(() => _languages = v))),
                    _selectTile('Eating Habits', _eatingHabits, () =>
                        _pickSingle(
                            title: 'Eating Habits',
                            options: _foodOptions,
                            current: _eatingHabits,
                            onPicked: (v) => setState(() => _eatingHabits = v))),
                    _selectTile('Smoking Habit', _smokingHabits, () =>
                        _pickSingle(
                            title: 'Smoking Habit',
                            options: const ['Any', 'Never', 'Occasionally'],
                            current: _smokingHabits,
                            onPicked: (v) => setState(() => _smokingHabits = v))),
                    _selectTile('Drinking Habit', _drinkingHabits, () =>
                        _pickSingle(
                            title: 'Drinking Habit',
                            options: const ['Any', 'Never', 'Occasionally'],
                            current: _drinkingHabits,
                            onPicked: (v) => setState(() => _drinkingHabits = v))),
                  ],
                ),
                _sectionCard(
                  icon: Icons.nightlight_round,
                  title: 'Religious & horoscope preferences',
                  subtitle: 'Religion, caste, and astrological details',
                  children: [
                    _selectTile('Religion', _religion, () => _pickSingle(
                        title: 'Religion',
                        options: _religionOptions,
                        current: _religion,
                        onPicked: (v) => setState(() => _religion = v))),
                    _selectTile('Caste', _caste, () => _pickSingle(
                        title: 'Caste',
                        options: _casteOptions,
                        current: _caste,
                        onPicked: (v) => setState(() {
                              _caste = v;
                              _subcaste = '';
                              if (v.isEmpty) _casteCompulsory = false;
                            }))),
                    _selectTile('Subcaste', _subcaste, () {
                      if (_caste.isEmpty) return;
                      _pickSingle(
                          title: 'Subcaste',
                          options: _filteredSubcastes,
                          current: _subcaste,
                          onPicked: (v) => setState(() => _subcaste = v));
                    }),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: _brand,
                      title: const Text('Caste is compulsory for matches',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      subtitle: const Text(
                          'When enabled, only profiles matching your caste and subcaste preferences are shown.',
                          style: TextStyle(fontSize: 11.5)),
                      value: _casteCompulsory,
                      onChanged: _caste.isEmpty
                          ? null
                          : (v) => setState(() => _casteCompulsory = v),
                    ),
                    const SizedBox(height: 4),
                    _selectTile('Star (Nakshatra)', _star, () => _pickSingle(
                        title: 'Star (Nakshatra)',
                        options: _stars,
                        current: _star,
                        onPicked: (v) => setState(() => _star = v))),
                    _selectTile('Raasi / Zodiac Sign', _raasiValue, () =>
                        _pickSingle(
                            title: 'Raasi / Zodiac Sign',
                            options: _raasi,
                            current: _raasiValue,
                            onPicked: (v) => setState(() => _raasiValue = v))),
                    _selectTile('Dosham', _dosham, () => _pickSingle(
                        title: 'Dosham',
                        options: const ['Any', 'No', 'Yes', "Doesn't Matter"],
                        current: _dosham,
                        onPicked: (v) => setState(() => _dosham = v))),
                  ],
                ),
                _sectionCard(
                  icon: Icons.work_outline_rounded,
                  title: 'Professional & location',
                  subtitle: 'Education, career, income, and location preferences',
                  children: [
                    _multiTile('Preferred Education Level', _education, () =>
                        _pickMulti(
                            title: 'Preferred Education Level',
                            options: _educationLevelOptions,
                            current: _education,
                            onPicked: (v) => setState(() => _education = v))),
                    _multiTile('Preferred Degree / Qualification', _degrees, () =>
                        _pickMulti(
                            title: 'Preferred Degree',
                            options: _degreeOptions,
                            current: _degrees,
                            onPicked: (v) => setState(() => _degrees = v))),
                    _multiTile('Preferred Specialization', _branchesSel, () =>
                        _pickMulti(
                            title: 'Preferred Specialization',
                            options: _branches,
                            current: _branchesSel,
                            onPicked: (v) => setState(() => _branchesSel = v))),
                    _multiTile('Preferred Employed In', _employedIn, () =>
                        _pickMulti(
                            title: 'Preferred Employed In',
                            options: _employmentTypes,
                            current: _employedIn,
                            onPicked: (v) => setState(() => _employedIn = v))),
                    _multiTile('Preferred Occupation', _occupation, () =>
                        _pickMulti(
                            title: 'Preferred Occupation',
                            options: _occupations,
                            current: _occupation,
                            onPicked: (v) => setState(() => _occupation = v))),
                    _selectTile('Preferred Annual Income (From)', _incomeMin,
                        () => _pickSingle(
                            title: 'Preferred Annual Income (From)',
                            options: _incomeOptions,
                            current: _incomeMin,
                            onPicked: (v) => setState(() => _incomeMin = v))),
                    _selectTile('Country', _country, () => _pickSingle(
                        title: 'Country',
                        options: _countries,
                        current: _country,
                        onPicked: (v) => setState(() => _country = v))),
                    _selectTile('State', _state, () => _pickSingle(
                        title: 'State',
                        options: _states,
                        current: _state,
                        onPicked: (v) => setState(() => _state = v))),
                    _selectTile('City', _city, () => _pickSingle(
                        title: 'City',
                        options: _cities,
                        current: _city,
                        onPicked: (v) => setState(() => _city = v))),
                  ],
                ),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Saving…' : 'Save preferences'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _brand,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
