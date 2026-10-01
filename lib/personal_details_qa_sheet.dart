import 'package:flutter/material.dart';

/// One-question-at-a-time version of the "Edit Basic Details" bottom sheet
/// in `profile_pages.dart`. Same fields, same required-field rules as
/// `_savePersonalDetails()` (name, date of birth, gender and "about" >= 100
/// chars are required; height is capped at 251cm if provided; everything
/// else is optional) — only the presentation changes.
///
/// This widget owns no persistence logic itself: it collects answers and
/// hands them back via [onSubmit] so the caller (`_UserDetailsPageState`)
/// can copy them into its own controllers and call the existing
/// `_savePersonalDetails()`, keeping the save/validation path identical to
/// the all-fields editor.
class PersonalDetailsQASheet extends StatefulWidget {
  const PersonalDetailsQASheet({
    super.key,
    required this.name,
    required this.dob,
    required this.age,
    required this.gender,
    required this.religion,
    required this.createdBy,
    required this.physicalStatus,
    required this.height,
    required this.weight,
    required this.skinColor,
    required this.bodyType,
    required this.maritalStatus,
    required this.foodPreference,
    required this.languages,
    required this.about,
    required this.genderOptions,
    required this.religionOptions,
    required this.createdByOptions,
    required this.physicalStatusOptions,
    required this.skinColorOptions,
    required this.bodyTypeOptions,
    required this.maritalStatusOptions,
    required this.foodPreferenceOptions,
    required this.indianLanguages,
    required this.internationalLanguages,
    required this.onSubmit,
  });

  final String name;
  final String dob;
  final String age;
  final String? gender;
  final String? religion;
  final String? createdBy;
  final String? physicalStatus;
  final String height;
  final String weight;
  final String? skinColor;
  final String? bodyType;
  final String? maritalStatus;
  final String? foodPreference;
  final List<String> languages;
  final String about;

  final List<String> genderOptions;
  final List<String> religionOptions;
  final List<String> createdByOptions;
  final List<String> physicalStatusOptions;
  final List<dynamic> skinColorOptions;
  final List<String> bodyTypeOptions;
  final List<String> maritalStatusOptions;
  final List<String> foodPreferenceOptions;
  final List<String> indianLanguages;
  final List<String> internationalLanguages;

  /// Called once, when the user reaches the last question and taps Save.
  final void Function(Map<String, dynamic> values) onSubmit;

  @override
  State<PersonalDetailsQASheet> createState() => _PersonalDetailsQASheetState();
}

class _PersonalDetailsQASheetState extends State<PersonalDetailsQASheet> {
  int _qIndex = 0;

  late final TextEditingController _nameCtrl = TextEditingController(text: widget.name);
  late final TextEditingController _heightCtrl = TextEditingController(text: widget.height);
  late final TextEditingController _weightCtrl = TextEditingController(text: widget.weight);
  late final TextEditingController _aboutCtrl = TextEditingController(text: widget.about);

  late String _dob = widget.dob;
  late String _age = widget.age;
  late String? _gender = widget.gender;
  late String? _religion = widget.religion;
  late String? _createdBy = widget.createdBy;
  late String? _physicalStatus = widget.physicalStatus;
  late String? _skinColor = widget.skinColor;
  late String? _bodyType = widget.bodyType;
  late String? _maritalStatus = widget.maritalStatus;
  late String? _foodPreference = widget.foodPreference;
  late List<String> _languages = List<String>.from(widget.languages);

  static const int _questionCount = 14;

  void _calculateAge(DateTime birthDate) {
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    _age = age.toString();
  }

  bool _isValid(int index) {
    switch (index) {
      case 0:
        return _nameCtrl.text.trim().isNotEmpty;
      case 1:
        return _dob.isNotEmpty;
      case 3:
        return _gender != null;
      case 6:
        if (_heightCtrl.text.isEmpty) return true;
        final h = int.tryParse(_heightCtrl.text);
        return h != null && h <= 251;
      case 13:
        return _aboutCtrl.text.trim().length >= 100;
      default:
        return true;
    }
  }

  String _titleFor(int index) {
    switch (index) {
      case 0:
        return "What's your full name?";
      case 1:
        return 'When were you born?';
      case 2:
        return "Who's creating this profile?";
      case 3:
        return "What's your gender?";
      case 4:
        return "What's your marital status?";
      case 5:
        return "What's your religion?";
      case 6:
        return 'How tall are you?';
      case 7:
        return "What's your weight?";
      case 8:
        return 'How would you describe your body type?';
      case 9:
        return "What's your skin tone?";
      case 10:
        return 'Any physical status we should know about?';
      case 11:
        return "What's your food preference?";
      case 12:
        return 'Which languages do you speak?';
      case 13:
        return 'Tell us about yourself';
    }
    return '';
  }

  String? _subtitleFor(int index) {
    switch (index) {
      case 1:
        return "We'll calculate your age automatically.";
      case 6:
        return 'In centimeters.';
      case 7:
        return 'In kilograms.';
      case 12:
        return 'Select all that apply.';
      case 13:
        return 'A short introduction for your profile (minimum 100 characters).';
    }
    return null;
  }

  Widget _dropdown(String? value, List<String> options, ValueChanged<String?> onChanged, {String hint = 'Select'}) {
    return DropdownButtonFormField<String>(
      initialValue: options.contains(value) ? value : null,
      onChanged: (v) => setState(() => onChanged(v)),
      hint: Text(hint),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      items: options
          .map((opt) => DropdownMenuItem<String>(value: opt, child: Text(opt)))
          .toList(),
    );
  }

  Widget _buildQuestionBody(int index) {
    switch (index) {
      case 0:
        return TextField(
          controller: _nameCtrl,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'e.g., Arjun Ramakrishnan',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      case 1:
        return GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(_dob) ?? DateTime.now().subtract(const Duration(days: 365 * 20)),
              firstDate: DateTime.now().subtract(const Duration(days: 365 * 100)),
              lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
            );
            if (picked != null) {
              setState(() {
                _dob = picked.toIso8601String().split('T')[0];
                _calculateAge(picked);
              });
            }
          },
          child: AbsorbPointer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: TextEditingController(text: _dob),
                  readOnly: true,
                  decoration: InputDecoration(
                    hintText: 'Select date of birth',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: const Icon(Icons.calendar_today, size: 18),
                  ),
                ),
                if (_age.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('That makes you $_age years old.', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                ],
              ],
            ),
          ),
        );
      case 2:
        return _dropdown(_createdBy, widget.createdByOptions, (v) => _createdBy = v, hint: 'Select creator');
      case 3:
        return _dropdown(_gender, widget.genderOptions, (v) => _gender = v, hint: 'Select gender');
      case 4:
        return _dropdown(_maritalStatus, widget.maritalStatusOptions, (v) => _maritalStatus = v, hint: 'Select marital status');
      case 5:
        return _dropdown(_religion, widget.religionOptions, (v) => _religion = v, hint: 'Select religion');
      case 6:
        return TextField(
          controller: _heightCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'e.g., 170',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      case 7:
        return TextField(
          controller: _weightCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'e.g., 65',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      case 8:
        return _dropdown(_bodyType, widget.bodyTypeOptions, (v) => _bodyType = v, hint: 'Select body type');
      case 9:
        return DropdownButtonFormField<String>(
          initialValue: widget.skinColorOptions.any((e) => e['value'] == _skinColor) ? _skinColor : null,
          onChanged: (v) => setState(() => _skinColor = v),
          hint: const Text('Select skin tone'),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          items: widget.skinColorOptions.map((opt) {
            final colorCode = opt['colour_code'] ?? '#000000';
            final colorValue = int.parse(colorCode.replaceFirst('#', '0xFF'));
            final color = Color(colorValue);
            return DropdownMenuItem<String>(
              value: opt['value'] as String,
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
                  ),
                  const SizedBox(width: 12),
                  Text(opt['value'] as String),
                ],
              ),
            );
          }).toList(),
        );
      case 10:
        return _dropdown(_physicalStatus, widget.physicalStatusOptions, (v) => _physicalStatus = v, hint: 'Select physical status');
      case 11:
        return _dropdown(_foodPreference, widget.foodPreferenceOptions, (v) => _foodPreference = v, hint: 'Select food preference');
      case 12:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._languages.map((lang) => Chip(
                  label: Text(lang, style: const TextStyle(fontSize: 12)),
                  onDeleted: () => setState(() => _languages.remove(lang)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  backgroundColor: const Color(0xFFD61A45).withOpacity(0.1),
                )),
            ActionChip(
              label: const Text('Add Language', style: TextStyle(fontSize: 12)),
              avatar: const Icon(Icons.add, size: 14),
              onPressed: () async {
                final allLangs = [...widget.indianLanguages, ...widget.internationalLanguages];
                final result = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Select Language'),
                    content: SizedBox(
                      width: double.maxFinite,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: allLangs.length,
                        itemBuilder: (ctx, i) => ListTile(
                          title: Text(allLangs[i]),
                          onTap: () => Navigator.pop(ctx, allLangs[i]),
                        ),
                      ),
                    ),
                  ),
                );
                if (result != null && !_languages.contains(result)) {
                  setState(() => _languages.add(result));
                }
              },
            ),
          ],
        );
      case 13:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _aboutCtrl,
              autofocus: true,
              maxLines: 5,
              maxLength: 600,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Example: I am a software engineer who loves trekking and classical music...',
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            Text(
              '${_aboutCtrl.text.length} / 600 ${_aboutCtrl.text.length < 100 ? "(min 100 chars required)" : ""}',
              style: TextStyle(fontSize: 12, color: _aboutCtrl.text.length < 100 ? Colors.orange : Colors.grey),
            ),
          ],
        );
    }
    return const SizedBox.shrink();
  }

  void _submit() {
    widget.onSubmit({
      'name': _nameCtrl.text,
      'dob': _dob,
      'age': _age,
      'gender': _gender,
      'religion': _religion,
      'createdBy': _createdBy,
      'physicalStatus': _physicalStatus,
      'height': _heightCtrl.text,
      'weight': _weightCtrl.text,
      'skinColor': _skinColor,
      'bodyType': _bodyType,
      'maritalStatus': _maritalStatus,
      'foodPreference': _foodPreference,
      'languages': _languages,
      'about': _aboutCtrl.text,
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _aboutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _qIndex == _questionCount - 1;
    final canContinue = _isValid(_qIndex);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Question ${_qIndex + 1} of $_questionCount',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD61A45))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_qIndex + 1) / _questionCount,
              minHeight: 6,
              backgroundColor: Colors.black12,
              valueColor: const AlwaysStoppedAnimation(Color(0xFFD61A45)),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Column(
                  key: ValueKey(_qIndex),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_titleFor(_qIndex), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    if (_subtitleFor(_qIndex) != null) ...[
                      const SizedBox(height: 6),
                      Text(_subtitleFor(_qIndex)!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                    ],
                    const SizedBox(height: 20),
                    _buildQuestionBody(_qIndex),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (_qIndex > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _qIndex--),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Back'),
                  ),
                ),
              if (_qIndex > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: !canContinue
                      ? null
                      : isLast
                          ? _submit
                          : () => setState(() => _qIndex++),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD61A45),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isLast ? 'Save' : 'Next'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
