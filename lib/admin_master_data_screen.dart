import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';

part 'admin_master_data_table_part.dart';

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
                          if (section.title == 'Personal Details') {
                            showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (sheetContext) => MasterDataListModalSheet(
                                stepId: item.id,
                                config: cfg,
                              ),
                            );
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => MasterDataTableScreen(
                                  stepId: item.id,
                                  config: cfg,
                                ),
                              ),
                            );
                          }
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

class MasterDataListPanel extends StatefulWidget {
  const MasterDataListPanel({
    super.key,
    required this.stepId,
    required this.config,
    this.listBottomPadding = 100,
  });

  final String stepId;
  final MasterTableConfig config;
  final double listBottomPadding;

  @override
  State<MasterDataListPanel> createState() => MasterDataListPanelState();
}

class MasterDataListPanelState extends State<MasterDataListPanel> with MasterDataListContentMixin<MasterDataListPanel> {
  @override
  String get masterDataStepId => widget.stepId;

  @override
  MasterTableConfig get masterDataConfig => widget.config;

  @override
  double get masterDataListBottomPadding => widget.listBottomPadding;

  @override
  Widget build(BuildContext context) => buildMasterDataListBody();
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
  final GlobalKey<MasterDataListPanelState> _panelKey = GlobalKey<MasterDataListPanelState>();

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
            onPressed: () => _panelKey.currentState?.refreshList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _panelKey.currentState?.openAdd(),
        backgroundColor: AdminHomeScreen.brandPurple,
        icon: const Icon(Icons.add_rounded),
        label: Text(widget.config.addButtonText),
      ),
      body: MasterDataListPanel(
        key: _panelKey,
        stepId: widget.stepId,
        config: widget.config,
        listBottomPadding: 100,
      ),
    );
  }
}

/// Large bottom sheet for Personal Details master lists (matches profile modal pattern).
class MasterDataListModalSheet extends StatefulWidget {
  const MasterDataListModalSheet({
    super.key,
    required this.stepId,
    required this.config,
  });

  final String stepId;
  final MasterTableConfig config;

  @override
  State<MasterDataListModalSheet> createState() => _MasterDataListModalSheetState();
}

class _MasterDataListModalSheetState extends State<MasterDataListModalSheet>
    with MasterDataListContentMixin<MasterDataListModalSheet> {
  @override
  String get masterDataStepId => widget.stepId;

  @override
  MasterTableConfig get masterDataConfig => widget.config;

  @override
  double get masterDataListBottomPadding => 16 + MediaQuery.of(context).padding.bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top > 0 ? 8 : 0),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Color(0xFFF8F9FE),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.config.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AdminHomeScreen.brandPurple,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Swipe down or tap close when done.',
                          style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: 0.45)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    color: AdminHomeScreen.brandPurple,
                    tooltip: 'Refresh',
                    onPressed: () => refreshList(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    color: AdminHomeScreen.brandPurple,
                    tooltip: widget.config.addButtonText,
                    onPressed: () => openAdd(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.black54,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => openAdd(),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(widget.config.addButtonText),
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminHomeScreen.brandPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
            Expanded(child: buildMasterDataListBody()),
          ],
        ),
      ),
    );
  }
}
