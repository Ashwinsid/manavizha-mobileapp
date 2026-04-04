import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';

// ---------------------------------------------------------------------------
// Mirrors manavizha/constants/master-data.ts
// ---------------------------------------------------------------------------

class MasterTableConfig {
  const MasterTableConfig({
    required this.tableName,
    required this.title,
    required this.addButtonText,
    required this.dialogTitle,
    required this.dialogDescription,
    this.inputPlaceholder,
  });

  final String tableName;
  final String title;
  final String addButtonText;
  final String dialogTitle;
  final String dialogDescription;
  final String? inputPlaceholder;
}

const Map<String, MasterTableConfig> kMasterTableConfigs = {
  'gender': MasterTableConfig(
    tableName: 'master_gender',
    title: 'Gender',
    addButtonText: 'Add Gender',
    dialogTitle: 'Add Gender',
    dialogDescription: 'Enter a new gender value to add to the list.',
    inputPlaceholder: 'e.g., Male, Female, Other',
  ),
  'skin-colour': MasterTableConfig(
    tableName: 'master_skin_colour',
    title: 'Skin Colour',
    addButtonText: 'Add Skin Colour',
    dialogTitle: 'Add Skin Colour',
    dialogDescription: 'Enter a new skin colour value to add to the list.',
    inputPlaceholder: 'e.g., Fair, Medium, Dark',
  ),
  'body-type': MasterTableConfig(
    tableName: 'master_body_type',
    title: 'Body Type',
    addButtonText: 'Add Body Type',
    dialogTitle: 'Add Body Type',
    dialogDescription: 'Enter a new body type value to add to the list.',
    inputPlaceholder: 'e.g., Slim, Average, Athletic',
  ),
  'marital-status': MasterTableConfig(
    tableName: 'master_marital_status',
    title: 'Marital Status',
    addButtonText: 'Add Marital Status',
    dialogTitle: 'Add Marital Status',
    dialogDescription: 'Enter a new marital status value to add to the list.',
    inputPlaceholder: 'e.g., Single, Married, Divorced',
  ),
  'food-preferences': MasterTableConfig(
    tableName: 'master_food_preferences',
    title: 'Food Preferences',
    addButtonText: 'Add Food Preference',
    dialogTitle: 'Add Food Preference',
    dialogDescription: 'Enter a new food preference value to add to the list.',
    inputPlaceholder: 'e.g., Vegetarian, Non-Vegetarian, Vegan',
  ),
  'indian-languages': MasterTableConfig(
    tableName: 'master_indian_languages',
    title: 'Indian Languages',
    addButtonText: 'Add Indian Language',
    dialogTitle: 'Add Indian Language',
    dialogDescription: 'Enter a new Indian language value to add to the list.',
    inputPlaceholder: 'e.g., Hindi, Tamil, Telugu',
  ),
  'international-languages': MasterTableConfig(
    tableName: 'master_international_languages',
    title: 'International Languages',
    addButtonText: 'Add International Language',
    dialogTitle: 'Add International Language',
    dialogDescription: 'Enter a new international language value to add to the list.',
    inputPlaceholder: 'e.g., English, French, Spanish',
  ),
  'education-level': MasterTableConfig(
    tableName: 'master_education_level',
    title: 'Education Level',
    addButtonText: 'Add Education Level',
    dialogTitle: 'Add Education Level',
    dialogDescription: 'Enter a new education level value to add to the list.',
    inputPlaceholder: "e.g., High School, Bachelor's, Master's",
  ),
  'degree-qualification': MasterTableConfig(
    tableName: 'master_degree_qualification',
    title: 'Degree/ Qualification',
    addButtonText: 'Add Degree/ Qualification',
    dialogTitle: 'Add Degree/ Qualification',
    dialogDescription: 'Enter a new degree/qualification value to add to the list.',
    inputPlaceholder: 'e.g., B.Tech, MBA, M.Sc',
  ),
  'status': MasterTableConfig(
    tableName: 'master_status',
    title: 'Status',
    addButtonText: 'Add Status',
    dialogTitle: 'Add Status',
    dialogDescription: 'Enter a new status value to add to the list.',
    inputPlaceholder: 'e.g., Active, Inactive, Pending',
  ),
  'employment-type': MasterTableConfig(
    tableName: 'master_employment_type',
    title: 'Employment Type',
    addButtonText: 'Add Employment Type',
    dialogTitle: 'Add Employment Type',
    dialogDescription: 'Enter a new employment type value to add to the list.',
    inputPlaceholder: 'e.g., Employee, Business, Student',
  ),
  'sector': MasterTableConfig(
    tableName: 'master_sector',
    title: 'Sector',
    addButtonText: 'Add Sector',
    dialogTitle: 'Add Sector',
    dialogDescription: 'Enter a new sector value to add to the list.',
    inputPlaceholder: 'e.g., IT, Finance, Healthcare',
  ),
  'type-of-business': MasterTableConfig(
    tableName: 'master_type_of_business',
    title: 'Type of Business',
    addButtonText: 'Add Type of Business',
    dialogTitle: 'Add Type of Business',
    dialogDescription: 'Enter a new type of business value to add to the list.',
    inputPlaceholder: 'e.g., Retail, Manufacturing, Services',
  ),
  'course-degree': MasterTableConfig(
    tableName: 'master_course_degree',
    title: 'Course/ Degree',
    addButtonText: 'Add Course/ Degree',
    dialogTitle: 'Add Course/ Degree',
    dialogDescription: 'Enter a new course/degree value to add to the list.',
    inputPlaceholder: 'e.g., Computer Science, Business Administration',
  ),
  'year-of-study': MasterTableConfig(
    tableName: 'master_year_of_study',
    title: 'Year of Study',
    addButtonText: 'Add Year of Study',
    dialogTitle: 'Add Year of Study',
    dialogDescription: 'Enter a new year of study value to add to the list.',
    inputPlaceholder: 'e.g., First Year, Second Year, Final Year',
  ),
  'caste': MasterTableConfig(
    tableName: 'master_caste',
    title: 'Caste',
    addButtonText: 'Add Caste',
    dialogTitle: 'Add Caste',
    dialogDescription: 'Enter a new caste value to add to the list.',
    inputPlaceholder: 'e.g., Brahmin, Kshatriya, Vaishya',
  ),
  'subcaste': MasterTableConfig(
    tableName: 'master_subcaste',
    title: 'Subcaste',
    addButtonText: 'Add Subcaste',
    dialogTitle: 'Add Subcaste',
    dialogDescription: 'Enter a new subcaste value to add to the list.',
    inputPlaceholder: 'Enter subcaste value',
  ),
  'kulam': MasterTableConfig(
    tableName: 'master_kulam',
    title: 'Kulam',
    addButtonText: 'Add Kulam',
    dialogTitle: 'Add Kulam',
    dialogDescription: 'Enter a new kulam value to add to the list.',
    inputPlaceholder: 'Enter kulam value',
  ),
  'gotram': MasterTableConfig(
    tableName: 'master_gotram',
    title: 'Gotram',
    addButtonText: 'Add Gotram',
    dialogTitle: 'Add Gotram',
    dialogDescription: 'Enter a new gotram value to add to the list.',
    inputPlaceholder: 'Enter gotram value',
  ),
  'family-type': MasterTableConfig(
    tableName: 'master_family_type',
    title: 'Family Type',
    addButtonText: 'Add Family Type',
    dialogTitle: 'Add Family Type',
    dialogDescription: 'Enter a new family type value to add to the list.',
    inputPlaceholder: 'e.g., Nuclear, Joint, Extended',
  ),
  'family-status': MasterTableConfig(
    tableName: 'master_family_status',
    title: 'Family Status',
    addButtonText: 'Add Family Status',
    dialogTitle: 'Add Family Status',
    dialogDescription: 'Enter a new family status value to add to the list.',
    inputPlaceholder: 'e.g., Middle Class, Upper Middle Class',
  ),
  'zodiac-moon-sign': MasterTableConfig(
    tableName: 'master_zodiac_moon_sign',
    title: 'Zodiac or Moon Sign',
    addButtonText: 'Add Zodiac or Moon Sign',
    dialogTitle: 'Add Zodiac or Moon Sign',
    dialogDescription: 'Enter a new zodiac or moon sign value to add to the list.',
    inputPlaceholder: 'e.g., Aries, Taurus, Gemini',
  ),
  'star': MasterTableConfig(
    tableName: 'master_star',
    title: 'Star',
    addButtonText: 'Add Star',
    dialogTitle: 'Add Star',
    dialogDescription: 'Enter a new star value to add to the list.',
    inputPlaceholder: 'e.g., Ashwini, Bharani, Krittika',
  ),
  'lagnam': MasterTableConfig(
    tableName: 'master_lagnam',
    title: 'Lagnam',
    addButtonText: 'Add Lagnam',
    dialogTitle: 'Add Lagnam',
    dialogDescription: 'Enter a new lagnam value to add to the list.',
    inputPlaceholder: 'Enter lagnam value',
  ),
  'hobbies': MasterTableConfig(
    tableName: 'master_hobbies',
    title: 'Hobbies',
    addButtonText: 'Add Hobby',
    dialogTitle: 'Add Hobby',
    dialogDescription: 'Enter a new hobby value to add to the list.',
    inputPlaceholder: 'e.g., Reading, Cooking, Traveling',
  ),
  'interests': MasterTableConfig(
    tableName: 'master_interests',
    title: 'Interests',
    addButtonText: 'Add Interest',
    dialogTitle: 'Add Interest',
    dialogDescription: 'Enter a new interest value to add to the list.',
    inputPlaceholder: 'e.g., Music, Sports, Art',
  ),
  'smoking': MasterTableConfig(
    tableName: 'master_smoking',
    title: 'Smoking',
    addButtonText: 'Add Smoking',
    dialogTitle: 'Add Smoking',
    dialogDescription: 'Enter a new smoking value to add to the list.',
    inputPlaceholder: 'e.g., Never, Occasionally, Regularly',
  ),
  'drinking': MasterTableConfig(
    tableName: 'master_drinking',
    title: 'Drinking',
    addButtonText: 'Add Drinking',
    dialogTitle: 'Add Drinking',
    dialogDescription: 'Enter a new drinking value to add to the list.',
    inputPlaceholder: 'e.g., Never, Occasionally, Socially',
  ),
  'parties': MasterTableConfig(
    tableName: 'master_parties',
    title: 'Parties',
    addButtonText: 'Add Parties',
    dialogTitle: 'Add Parties',
    dialogDescription: 'Enter a new parties value to add to the list.',
    inputPlaceholder: 'e.g., Never, Occasionally, Regularly',
  ),
  'pubs': MasterTableConfig(
    tableName: 'master_pubs',
    title: 'Pubs',
    addButtonText: 'Add Pubs',
    dialogTitle: 'Add Pubs',
    dialogDescription: 'Enter a new pubs value to add to the list.',
    inputPlaceholder: 'e.g., Never, Occasionally, Regularly',
  ),
};

class MasterDataMenuSection {
  const MasterDataMenuSection({required this.title, required this.items});
  final String title;
  final List<({String id, String title})> items;
}

const List<MasterDataMenuSection> kMasterDataMenu = [
  MasterDataMenuSection(
    title: 'Personal Details',
    items: [
      (id: 'gender', title: 'Gender'),
      (id: 'skin-colour', title: 'Skin Colour'),
      (id: 'body-type', title: 'Body Type'),
      (id: 'marital-status', title: 'Marital Status'),
      (id: 'food-preferences', title: 'Food Preferences'),
      (id: 'indian-languages', title: 'Indian Languages'),
      (id: 'international-languages', title: 'International Languages'),
    ],
  ),
  MasterDataMenuSection(
    title: 'Educational Details',
    items: [
      (id: 'education-level', title: 'Education Level'),
      (id: 'status', title: 'Status'),
    ],
  ),
  MasterDataMenuSection(
    title: 'Professional Details',
    items: [
      (id: 'employment-type', title: 'Employment Type'),
      (id: 'sector', title: 'Sector'),
      (id: 'type-of-business', title: 'Type of Business'),
      (id: 'year-of-study', title: 'Year of Study'),
    ],
  ),
  MasterDataMenuSection(
    title: 'Horoscope Details',
    items: [
      (id: 'zodiac-moon-sign', title: 'Zodiac or Moon Sign'),
      (id: 'star', title: 'Star'),
      (id: 'lagnam', title: 'Lagnam'),
    ],
  ),
  MasterDataMenuSection(
    title: 'Interests',
    items: [
      (id: 'hobbies', title: 'Hobbies'),
      (id: 'interests', title: 'Interests'),
    ],
  ),
  MasterDataMenuSection(
    title: 'Social Habits',
    items: [
      (id: 'smoking', title: 'Smoking'),
      (id: 'drinking', title: 'Drinking'),
      (id: 'parties', title: 'Parties'),
      (id: 'pubs', title: 'Pubs'),
    ],
  ),
  MasterDataMenuSection(
    title: 'Family Details',
    items: [
      (id: 'caste', title: 'Caste'),
      (id: 'subcaste', title: 'Subcaste'),
      (id: 'kulam', title: 'Kulam'),
      (id: 'gotram', title: 'Gotram'),
      (id: 'family-type', title: 'Family Type'),
      (id: 'family-status', title: 'Family Status'),
    ],
  ),
];

bool _showColourCode(String stepId) => stepId == 'skin-colour';
bool _showCategory(String stepId) => stepId == 'education-level';

final RegExp _hexPattern = RegExp(r'^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$');

Color? _tryParseHex(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final s = raw.trim();
  if (!_hexPattern.hasMatch(s)) return null;
  var hex = s.substring(1);
  if (hex.length == 3) {
    hex = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
  }
  return Color(int.parse('FF$hex', radix: 16));
}

// ---------------------------------------------------------------------------
// Menu screen (sidebar → mobile: expansion list)
// ---------------------------------------------------------------------------

class AdminMasterDataScreen extends StatelessWidget {
  const AdminMasterDataScreen({super.key});

  static const Color _pageBackground = Color(0xFFF8F9FE);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        backgroundColor: _pageBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: AdminHomeScreen.brandPurple,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(Icons.storage_rounded, color: AdminHomeScreen.brandPurple.withValues(alpha: 0.9)),
            const SizedBox(width: 10),
            const Text(
              'Master Data',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AdminHomeScreen.brandPurple,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Choose a category, then pick a list to view or edit values.',
            style: TextStyle(
              fontSize: 14,
              height: 1.35,
              color: Colors.black.withValues(alpha: 0.52),
            ),
          ),
          const SizedBox(height: 16),
          ...kMasterDataMenu.map((section) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
                    ),
                    collapsedShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
                    ),
                    title: Text(
                      section.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF1E1E1E),
                      ),
                    ),
                    children: section.items.map((item) {
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        leading: Icon(
                          Icons.circle_outlined,
                          size: 18,
                          color: AdminHomeScreen.brandPurple.withValues(alpha: 0.65),
                        ),
                        title: Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, size: 22),
                        onTap: () {
                          final cfg = kMasterTableConfigs[item.id];
                          if (cfg == null) return;
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => MasterDataTableScreen(
                                stepId: item.id,
                                config: cfg,
                              ),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Table / CRUD (mirrors master-data-manager.tsx)
// ---------------------------------------------------------------------------

class _MasterRow {
  _MasterRow({
    required this.id,
    required this.value,
    this.colourCode,
    this.category,
  });

  final String id;
  final String value;
  final String? colourCode;
  final String? category;

  factory _MasterRow.fromJson(Map<String, dynamic> j) {
    return _MasterRow(
      id: j['id']?.toString() ?? '',
      value: j['value'] as String? ?? '',
      colourCode: j['colour_code'] as String?,
      category: j['category'] as String?,
    );
  }
}

class MasterDataTableScreen extends StatefulWidget {
  const MasterDataTableScreen({
    super.key,
    required this.stepId,
    required this.config,
  });

  final String stepId;
  final MasterTableConfig config;

  @override
  State<MasterDataTableScreen> createState() => _MasterDataTableScreenState();
}

class _MasterDataTableScreenState extends State<MasterDataTableScreen> {
  static const Color _pageBackground = Color(0xFFF8F9FE);

  List<_MasterRow> _rows = [];
  bool _loading = true;
  String? _error;

  bool get _colour => _showColourCode(widget.stepId);
  bool get _category => _showCategory(widget.stepId);

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Supabase.instance.client
          .from(widget.config.tableName)
          .select()
          .order('created_at', ascending: true);
      final list = (data as List<dynamic>).map((e) => _MasterRow.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (mounted) {
        setState(() {
          _rows = list;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Master data fetch error: $e');
      if (mounted) {
        setState(() {
          _error = 'Could not load data. Check permissions and table name.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openEditor({_MasterRow? existing}) async {
    final valueCtrl = TextEditingController(text: existing?.value ?? '');
    final colourCtrl = TextEditingController(text: existing?.colourCode ?? '');
    final categoryCtrl = TextEditingController(text: existing?.category ?? '');
    final isEdit = existing != null;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (context, setModal) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isEdit ? 'Edit ${widget.config.title}' : widget.config.dialogTitle,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isEdit
                          ? 'Update the ${widget.config.title.toLowerCase()} value below.'
                          : widget.config.dialogDescription,
                      style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.55)),
                    ),
                    const SizedBox(height: 20),
                    if (_category) ...[
                      TextField(
                        controller: categoryCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          hintText: 'Enter category',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: valueCtrl,
                      decoration: InputDecoration(
                        labelText: '${widget.config.title} value',
                        hintText: widget.config.inputPlaceholder,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (_colour) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: colourCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Colour code (HEX)',
                          hintText: '#FF5733 or #F53',
                          border: OutlineInputBorder(),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[#A-Fa-f0-9]')),
                          LengthLimitingTextInputFormatter(7),
                        ],
                        onChanged: (v) {
                          if (v.isNotEmpty && !v.startsWith('#')) {
                            colourCtrl.text = '#$v';
                            colourCtrl.selection = TextSelection.collapsed(offset: colourCtrl.text.length);
                          }
                          setModal(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter a valid HEX color code (e.g., #FF5733 or #F53)',
                        style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45)),
                      ),
                      if (_tryParseHex(colourCtrl.text) != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _tryParseHex(colourCtrl.text),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.black12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminHomeScreen.brandPurple,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final ok = await _saveRow(
                          context: ctx,
                          existingId: existing?.id,
                          valueCtrl: valueCtrl,
                          colourCtrl: colourCtrl,
                          categoryCtrl: categoryCtrl,
                        );
                        if (ok == true && ctx.mounted) Navigator.of(ctx).pop(true);
                      },
                      child: Text(isEdit ? 'Update' : 'Save'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    valueCtrl.dispose();
    colourCtrl.dispose();
    categoryCtrl.dispose();

    if (saved == true && mounted) await _fetch();
  }

  Future<bool?> _saveRow({
    required BuildContext context,
    required String? existingId,
    required TextEditingController valueCtrl,
    required TextEditingController colourCtrl,
    required TextEditingController categoryCtrl,
  }) async {
    final v = valueCtrl.text.trim();
    if (v.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a ${widget.config.title.toLowerCase()} value')),
      );
      return false;
    }

    if (_colour) {
      final hex = colourCtrl.text.trim().toUpperCase();
      if (hex.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a colour code (HEX)')));
        return false;
      }
      if (!_hexPattern.hasMatch(hex)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid HEX color code (e.g., #FF5733 or #F53)')),
        );
        return false;
      }
    }

    if (_category && categoryCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a category')));
      return false;
    }

    final payload = <String, dynamic>{'value': v};
    if (_colour) {
      payload['colour_code'] = colourCtrl.text.trim().toUpperCase();
    }
    if (_category) {
      payload['category'] = categoryCtrl.text.trim();
    }

    try {
      if (existingId != null) {
        await Supabase.instance.client.from(widget.config.tableName).update(payload).eq('id', existingId);
      } else {
        await Supabase.instance.client.from(widget.config.tableName).insert(payload);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(existingId != null ? 'Updated successfully' : 'Added successfully')),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Master data save error: $e');
      if (e is PostgrestException && e.code == '23505') {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('This ${widget.config.title.toLowerCase()} value already exists')),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save: ${e is PostgrestException ? e.message : e}')),
          );
        }
      }
      return false;
    }
  }

  Future<void> _confirmDelete(_MasterRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.config.title} value'),
        content: Text('Are you sure you want to delete "${row.value}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await Supabase.instance.client.from(widget.config.tableName).delete().eq('id', row.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
        await _fetch();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _pageBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: AdminHomeScreen.brandPurple,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.config.title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AdminHomeScreen.brandPurple,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: AdminHomeScreen.brandPurple,
            onPressed: _loading ? null : _fetch,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: AdminHomeScreen.brandPurple,
        icon: const Icon(Icons.add_rounded),
        label: Text(widget.config.addButtonText),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AdminHomeScreen.brandPurple))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  color: AdminHomeScreen.brandPurple,
                  onRefresh: _fetch,
                  child: _rows.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                            Icon(Icons.inbox_outlined, size: 56, color: Colors.black.withValues(alpha: 0.2)),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'No ${widget.config.title.toLowerCase()} values yet. Tap "${widget.config.addButtonText}" to add one.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.black.withValues(alpha: 0.5), height: 1.4),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: _rows.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            final swatch = _tryParseHex(row.colourCode);
                            return Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _openEditor(existing: row),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 28,
                                        child: Text(
                                          '${index + 1}.',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Colors.black.withValues(alpha: 0.35),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (_category && (row.category ?? '').isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(bottom: 4),
                                                child: Text(
                                                  row.category!,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AdminHomeScreen.brandPurple.withValues(alpha: 0.85),
                                                  ),
                                                ),
                                              ),
                                            Text(
                                              row.value,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF1E1E1E),
                                              ),
                                            ),
                                            if (_colour) ...[
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  if (swatch != null)
                                                    Container(
                                                      width: 28,
                                                      height: 28,
                                                      margin: const EdgeInsets.only(right: 8),
                                                      decoration: BoxDecoration(
                                                        color: swatch,
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: Colors.black12),
                                                      ),
                                                    ),
                                                  Text(
                                                    row.colourCode ?? '—',
                                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.edit_outlined, color: AdminHomeScreen.brandPurple.withValues(alpha: 0.85)),
                                        onPressed: () => _openEditor(existing: row),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade400),
                                        onPressed: () => _confirmDelete(row),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
