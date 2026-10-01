import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_extended_details.dart';
import 'user_profile_completion.dart';
import 'partner_preferences_screen.dart';
import 'personal_details_qa_sheet.dart';
import 'contact_details_logic.dart';
import 'contact_details_qa_sheet.dart';
import 'member_settings_screen.dart';

class UserDetailsPage extends StatefulWidget {
  const UserDetailsPage({super.key});

  @override
  State<UserDetailsPage> createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage> {
  String? _profilePhotoUrl;
  Map<String, dynamic>? _contactData;
  bool _isLoadingPhoto = true;
  bool _isLoadingData = true;

  // Personal Details State
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _dobCtrl = TextEditingController();
  final TextEditingController _ageCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _weightCtrl = TextEditingController();
  final TextEditingController _aboutCtrl = TextEditingController();

  String? _selectedGender;
  String? _selectedReligion;
  String? _selectedCreatedBy;
  String? _selectedPhysicalStatus;
  String? _selectedSkinColor;
  String? _selectedBodyType;
  String? _selectedMaritalStatus;
  String? _selectedFoodPreference;
  List<String> _selectedLanguages = [];

  // Master Data Lists
  List<String> _genderOptions = ['Male', 'Female'];
  List<String> _religionOptions = [];
  List<String> _createdByOptions = ['Self', 'Parents', 'Sibling', 'Relative', 'Friend'];
  List<String> _physicalStatusOptions = ['Normal', 'Physically Challenged'];
  List<dynamic> _skinColorOptions = [
    {'value': 'Fair', 'colour_code': '#FCD5B5'},
    {'value': 'Wheatish', 'colour_code': '#E1B382'},
    {'value': 'Dark', 'colour_code': '#8D5524'}
  ];
  List<String> _bodyTypeOptions = ['Slim', 'Average', 'Athletic', 'Heavy'];
  List<String> _maritalStatusOptions = ['Never Married', 'Divorced', 'Widowed', 'Awaiting Divorce'];
  List<String> _foodPreferenceOptions = ['Vegetarian', 'Non-Vegetarian', 'Eggetarian', 'Vegan'];
  List<String> _indianLanguages = ['Tamil', 'English', 'Hindi', 'Telugu', 'Malayalam', 'Kannada'];
  List<String> _internationalLanguages = ['English', 'French', 'German', 'Spanish'];

  // Social Habits State
  String? _selectedSmoking;
  String? _selectedDrinking;
  String? _selectedParties;
  String? _selectedPubs;

  // Social Master Data
  List<String> _smokingOptions = ['Never', 'Occasional', 'Regular'];
  List<String> _drinkingOptions = ['Never', 'Occasional', 'Regular'];
  List<String> _partiesOptions = ['Never', 'Occasional', 'Regular'];
  List<String> _pubsOptions = ['Never', 'Occasional', 'Regular'];

  // Interests (hobbies + interests from master tables, stored in `interests`)
  List<String> _selectedHobbies = [];
  List<String> _selectedInterests = [];
  List<String> _hobbyMasterOptions = [];
  List<String> _interestMasterOptions = [];

  List<Map<String, dynamic>> _educationRows = [];
  String _professionType = 'none';
  String _employmentLabel = 'Private';
  Map<String, dynamic> _empProf = {};
  Map<String, dynamic> _busProf = {};
  Map<String, dynamic> _stuProf = {};
  Map<String, dynamic> _familyMap = {};
  Map<String, dynamic> _horoscopeMap = {};
  UserDetailsSectionCompletion? _sectionCompletion;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await Future.wait([
      _fetchProfilePhoto(),
      _fetchMasterData(),
      _fetchPersonalDetails(),
      _fetchSocialHabits(),
      _fetchInterestsDetails(),
      _fetchEducationDetails(),
      _fetchProfessionDetails(),
      _fetchFamilyDetails(),
      _fetchHoroscopeDetails(),
      _fetchSectionCompletion(),
    ]);
    if (mounted) setState(() => _isLoadingData = false);
  }

  Future<void> _fetchSectionCompletion() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final snap = await loadUserProfileSnapshot(Supabase.instance.client, userId);
      if (mounted) setState(() => _sectionCompletion = snap.sections);
    } catch (e) {
      debugPrint('Error loading section completion: $e');
    }
  }

  int _sectionPercentFor(String title) {
    final s = _sectionCompletion;
    if (s == null) return 0;
    switch (title) {
      case 'Basic Details':
        return s.basicDetails;
      case 'Contact Details':
        return s.contactDetails;
      case 'Educational Details':
        return s.educationalDetails;
      case 'Professional Details':
        return s.professionalDetails;
      case 'Family Details':
        return s.familyDetails;
      case 'Horoscope Details':
        return s.horoscopeDetails;
      case 'Interests':
        return s.interests;
      case 'Social Habits':
        return s.socialHabits;
      default:
        return 0;
    }
  }

  Widget _sectionPercentBadge(String title) {
    final p = _sectionPercentFor(title).clamp(0, 100);
    final color = p >= 100
        ? const Color(0xFF15803D)
        : (p > 0 ? const Color(0xFFD61A45) : const Color(0xFF737373));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$p%',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  Future<void> _fetchEducationDetails() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final rows = await ProfileExtendedRepository.fetchEducation(userId);
      if (mounted) setState(() => _educationRows = rows);
    } catch (e) {
      debugPrint('Error fetching education: $e');
    }
  }

  Future<void> _fetchProfessionDetails() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final t = await ProfileExtendedRepository.fetchProfession(userId);
      if (!mounted) return;
      setState(() {
        _empProf = t.emp ?? {};
        _busProf = t.bus ?? {};
        _stuProf = t.stu ?? {};
        _professionType = ProfileExtendedRepository.detectProfessionType(_empProf, _busProf, _stuProf);
        _employmentLabel = _inferEmploymentLabel();
      });
    } catch (e) {
      debugPrint('Error fetching profession: $e');
    }
  }

  Future<void> _fetchFamilyDetails() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final m = await ProfileExtendedRepository.fetchFamily(userId);
      if (mounted) setState(() => _familyMap = m);
    } catch (e) {
      debugPrint('Error fetching family: $e');
    }
  }

  Future<void> _fetchHoroscopeDetails() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final m = await ProfileExtendedRepository.fetchHoroscope(userId);
      if (mounted) setState(() => _horoscopeMap = m);
    } catch (e) {
      debugPrint('Error fetching horoscope: $e');
    }
  }

  void _openEducationEditor() {
    showEducationDetailsQASheet(
      context,
      initialRows: List<Map<String, dynamic>>.from(_educationRows.map((e) => Map<String, dynamic>.from(e))),
      onSaved: (savedRows) {
        final pct = computeEducationDetailsCompletionPercent(savedRows);
        if (mounted) {
          final s = _sectionCompletion;
          if (s != null) setState(() => _sectionCompletion = s.copyWith(educationalDetails: pct));
        }
        _fetchEducationDetails().then((_) {
          if (mounted) _fetchSectionCompletion();
        });
      },
    );
  }

  String _inferEmploymentLabel() {
    switch (_professionType) {
      case 'student':
        return 'Student';
      case 'business':
        return 'Business';
      case 'employee':
        return 'Private';
      case 'not_working':
        return 'Not Working';
      default:
        return 'Private';
    }
  }

  void _openProfessionEditor() {
    showProfessionDetailsQASheet(
      context,
      initialEmploymentType: _employmentLabel,
      emp: Map<String, dynamic>.from(_empProf),
      bus: Map<String, dynamic>.from(_busProf),
      stu: Map<String, dynamic>.from(_stuProf),
      onSaved: (category, employmentLabel, emp, bus, stu) {
        // The sheet reports "Not Working" as category 'none' (its save bucket);
        // distinguish it from "nothing saved" so it counts as complete, like web.
        final effectiveType = category == 'none' && employmentLabel.trim().toLowerCase() == 'not working'
            ? 'not_working'
            : category;
        final pct = computeProfessionSectionPercentForType(effectiveType, emp, bus, stu);
        if (mounted) {
          setState(() {
            _employmentLabel = employmentLabel;
            _professionType = effectiveType;
            _empProf = Map<String, dynamic>.from(emp);
            _busProf = Map<String, dynamic>.from(bus);
            _stuProf = Map<String, dynamic>.from(stu);
            final s = _sectionCompletion;
            if (s != null) {
              _sectionCompletion = s.copyWith(professionalDetails: pct);
            }
          });
        }
        _fetchProfessionDetails().then((_) {
          if (mounted) _fetchSectionCompletion();
        });
      },
    );
  }

  void _openFamilyEditor() {
    showFamilyDetailsQASheet(
      context,
      initial: Map<String, dynamic>.from(_familyMap),
      onSaved: (saved) {
        final pct = computeFamilyDetailsCompletionPercent(saved);
        if (mounted) {
          final s = _sectionCompletion;
          if (s != null) {
            setState(() => _sectionCompletion = s.copyWith(familyDetails: pct));
          }
        }
        _fetchFamilyDetails().then((_) {
          if (mounted) _fetchSectionCompletion();
        });
      },
    );
  }

  void _openHoroscopeEditor() {
    showHoroscopeDetailsQASheet(
      context,
      initial: Map<String, dynamic>.from(_horoscopeMap),
      onSaved: (saved) {
        final pct = computeHoroscopeCompletionPercent(saved);
        if (mounted) {
          final s = _sectionCompletion;
          if (s != null) setState(() => _sectionCompletion = s.copyWith(horoscopeDetails: pct));
        }
        _fetchHoroscopeDetails().then((_) {
          if (mounted) _fetchSectionCompletion();
        });
      },
    );
  }

  String _professionSummaryLine() {
    if (_professionType == 'employee' && _empProf.isNotEmpty) {
      final d = _empProf['designation']?.toString() ?? '';
      final c = _empProf['company']?.toString() ?? '';
      if (d.isNotEmpty || c.isNotEmpty) {
        return [d, c].where((s) => s.isNotEmpty).join(' at ');
      }
    }
    if (_professionType == 'business' && _busProf.isNotEmpty) {
      final n = _busProf['business_name']?.toString() ?? '';
      final d = _busProf['designation']?.toString() ?? '';
      if (n.isNotEmpty) return d.isNotEmpty ? '$d — $n' : n;
    }
    if (_professionType == 'student' && _stuProf.isNotEmpty) {
      final co = _stuProf['course']?.toString() ?? '';
      final ins = _stuProf['institution']?.toString() ?? '';
      if (co.isNotEmpty || ins.isNotEmpty) return [co, ins].where((s) => s.isNotEmpty).join(' — ');
    }
    return '';
  }

  Future<void> _fetchMasterData() async {
    try {
      final supabase = Supabase.instance.client;
      
      final results = await Future.wait([
        supabase.from('master_gender').select('value'),
        supabase.from('master_skin_colour').select('value, colour_code'),
        supabase.from('master_body_type').select('value'),
        supabase.from('master_marital_status').select('value'),
        supabase.from('master_food_preferences').select('value'),
        supabase.from('master_indian_languages').select('value'),
        supabase.from('master_international_languages').select('value'),
        supabase.from('master_smoking').select('value'),
        supabase.from('master_drinking').select('value'),
        supabase.from('master_parties').select('value'),
        supabase.from('master_pubs').select('value'),
        supabase.from('master_hobbies').select('value'),
        supabase.from('master_interests').select('value'),
        supabase.from('master_religion').select('value'),
      ]);

      if (mounted) {
        setState(() {
          if ((results[0] as List).isNotEmpty) _genderOptions = (results[0] as List).map((e) => e['value'] as String).toList();
          if ((results[1] as List).isNotEmpty) _skinColorOptions = results[1] as List;
          if ((results[2] as List).isNotEmpty) _bodyTypeOptions = (results[2] as List).map((e) => e['value'] as String).toList();
          if ((results[3] as List).isNotEmpty) _maritalStatusOptions = (results[3] as List).map((e) => e['value'] as String).toList();
          if ((results[4] as List).isNotEmpty) _foodPreferenceOptions = (results[4] as List).map((e) => e['value'] as String).toList();
          if ((results[5] as List).isNotEmpty) _indianLanguages = (results[5] as List).map((e) => e['value'] as String).toList();
          if ((results[6] as List).isNotEmpty) _internationalLanguages = (results[6] as List).map((e) => e['value'] as String).toList();
          
          if (results[13] is List && (results[13] as List).isNotEmpty) {
            _religionOptions = (results[13] as List).map((e) => e['value'] as String).toList();
          }
          
          if (results[7] is List && (results[7] as List).isNotEmpty) {
            _smokingOptions = (results[7] as List).map((e) => e['value'] as String).toList();
          }
          if (results[8] is List && (results[8] as List).isNotEmpty) {
            _drinkingOptions = (results[8] as List).map((e) => e['value'] as String).toList();
          }
          if (results[9] is List && (results[9] as List).isNotEmpty) {
            _partiesOptions = (results[9] as List).map((e) => e['value'] as String).toList();
          }
          if (results[10] is List && (results[10] as List).isNotEmpty) {
            _pubsOptions = (results[10] as List).map((e) => e['value'] as String).toList();
          }
          if (results[11] is List && (results[11] as List).isNotEmpty) {
            _hobbyMasterOptions = (results[11] as List).map((e) => e['value'] as String).toList();
          }
          if (results[12] is List && (results[12] as List).isNotEmpty) {
            _interestMasterOptions = (results[12] as List).map((e) => e['value'] as String).toList();
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching master data: $e');
    }
  }

  Future<void> _fetchPersonalDetails() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final data = await Supabase.instance.client
          .from('personal_details')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      final contactData = await Supabase.instance.client
          .from('contact_details')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (mounted) { _contactData = contactData; }
      if (data != null && mounted) {
        setState(() {
          _nameCtrl.text = data['name'] ?? '';
          _dobCtrl.text = data['date_of_birth'] ?? '';
          _ageCtrl.text = data['age']?.toString() ?? '';
          _heightCtrl.text = data['height']?.toString() ?? '';
          _weightCtrl.text = data['weight']?.toString() ?? '';
          _aboutCtrl.text = data['about'] ?? '';
          _selectedGender = data['sex'];
          _selectedReligion = data['religion'];
          _selectedCreatedBy = data['created_by'];
          _selectedPhysicalStatus = data['physical_status'];
          _selectedSkinColor = data['skin_color'];
          _selectedBodyType = data['body_type'];
          _selectedMaritalStatus = data['marital_status'];
          _selectedFoodPreference = data['food_preference'];
          _selectedLanguages = List<String>.from(data['languages'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('Error fetching personal details: $e');
    }
  }

  Future<void> _fetchSocialHabits() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final data = await Supabase.instance.client
          .from('social_habits')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _selectedSmoking = data['smoking'];
          _selectedDrinking = data['drinking'];
          _selectedParties = data['parties'];
          _selectedPubs = data['pubs'];
        });
      }
    } catch (e) {
      debugPrint('Error fetching social habits: $e');
    }
  }

  Future<void> _fetchInterestsDetails() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final data = await Supabase.instance.client
          .from('interests')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _selectedHobbies = List<String>.from(data['hobbies'] ?? []);
          _selectedInterests = List<String>.from(data['interests'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('Error fetching interests: $e');
    }
  }

  Future<void> _fetchProfilePhoto() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoadingPhoto = false);
        return;
      }

      final data = await Supabase.instance.client
          .from('photos')
          .select('user_photos')
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null && data['user_photos'] != null && (data['user_photos'] as List).isNotEmpty) {
        if (mounted) {
          setState(() {
            _profilePhotoUrl = data['user_photos'][0];
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching profile photo: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingPhoto = false);
      }
    }
  }

  void _calculateAge(DateTime birthDate) {
    DateTime today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    _ageCtrl.text = age.toString();
  }

  Future<void> _savePersonalDetails() async {
    // Validation
    if (_nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    if (_dobCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Date of Birth is required')));
      return;
    }
    if (_selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gender is required')));
      return;
    }
    if (_heightCtrl.text.isNotEmpty && int.parse(_heightCtrl.text) > 251) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Height cannot exceed 251cm')));
      return;
    }
    if (_aboutCtrl.text.length < 100) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('About yourself must be at least 100 characters')));
      return;
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      setState(() => _isLoadingData = true);

      final personalRow = <String, dynamic>{
        'user_id': userId,
        'name': _nameCtrl.text,
        'date_of_birth': _dobCtrl.text,
        'age': int.tryParse(_ageCtrl.text),
        'created_by': _selectedCreatedBy,
        'physical_status': _selectedPhysicalStatus,
        'sex': _selectedGender,
        'religion': _selectedReligion,
        'height': int.tryParse(_heightCtrl.text),
        'weight': int.tryParse(_weightCtrl.text),
        'skin_color': _selectedSkinColor,
        'body_type': _selectedBodyType,
        'marital_status': _selectedMaritalStatus,
        'food_preference': _selectedFoodPreference,
        'languages': _selectedLanguages,
        'about': _aboutCtrl.text,
        'updated_at': DateTime.now().toIso8601String(),
      };
      personalRow['completion_percentage'] = computePersonalDetailsCompletionPercent(personalRow);
      await Supabase.instance.client.from('personal_details').upsert(personalRow, onConflict: 'user_id');

      if (mounted) {
        final s = _sectionCompletion;
        final pct = computePersonalDetailsCompletionPercent(personalRow);
        if (s != null) setState(() => _sectionCompletion = s.copyWith(basicDetails: pct));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Basic details saved successfully!')));
        Navigator.pop(context); // Close the editor modal
        _fetchPersonalDetails().then((_) {
          if (mounted) _fetchSectionCompletion();
        });
      }
    } catch (e) {
      debugPrint('Error saving personal details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save details!')));
      }
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  Future<void> _saveSocialHabits() async {
    final allSelected = [_selectedSmoking, _selectedDrinking, _selectedParties, _selectedPubs]
        .every((v) => (v?.trim() ?? '').isNotEmpty);
    if (!allSelected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select all social habits')));
      return;
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      setState(() => _isLoadingData = true);

      final socialRow = <String, dynamic>{
        'user_id': userId,
        'smoking': _selectedSmoking,
        'drinking': _selectedDrinking,
        'parties': _selectedParties,
        'pubs': _selectedPubs,
        'updated_at': DateTime.now().toIso8601String(),
      };
      socialRow['completion_percentage'] = computeSocialHabitsCompletionPercent(socialRow);
      await Supabase.instance.client.from('social_habits').upsert(socialRow, onConflict: 'user_id');

      if (mounted) {
        final s = _sectionCompletion;
        final pct = computeSocialHabitsCompletionPercent(socialRow);
        if (s != null) setState(() => _sectionCompletion = s.copyWith(socialHabits: pct));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Social habits saved successfully!')));
        Navigator.pop(context);
        _fetchSocialHabits().then((_) {
          if (mounted) _fetchSectionCompletion();
        });
      }
    } catch (e) {
      debugPrint('Error saving social habits: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save social habits')));
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  Future<void> _saveInterests({required List<String> hobbies, required List<String> interests}) async {
    if (hobbies.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 3 hobbies')),
      );
      return;
    }
    if (interests.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least 3 interests')),
      );
      return;
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      setState(() => _isLoadingData = true);

      final completionPct = computeInterestsSectionPercent({'hobbies': hobbies, 'interests': interests});

      await Supabase.instance.client.from('interests').upsert({
        'user_id': userId,
        'hobbies': hobbies,
        'interests': interests,
        'completion_percentage': completionPct,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      if (mounted) {
        final s = _sectionCompletion;
        if (s != null) {
          setState(() {
            _sectionCompletion = s.copyWith(interests: completionPct);
            _selectedHobbies = List<String>.from(hobbies);
            _selectedInterests = List<String>.from(interests);
          });
        } else {
          setState(() {
            _selectedHobbies = List<String>.from(hobbies);
            _selectedInterests = List<String>.from(interests);
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Interests saved successfully!')),
        );
        Navigator.pop(context);
        _fetchInterestsDetails().then((_) {
          if (mounted) _fetchSectionCompletion();
        });
      }
    } catch (e) {
      debugPrint('Error saving interests: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save interests')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  /// One-question-at-a-time editor for Interests, mirroring
  /// manavizha/components/profile-steps/interests-qa.tsx (hobbies, then
  /// interests). Keeps the mobile "at least 3 of each" rule and the same
  /// `_saveInterests()` write path as before.
  void _showInterestsEditor() {
    List<String> localHobbies = List<String>.from(_selectedHobbies);
    List<String> localInterests = List<String>.from(_selectedInterests);
    int qIndex = 0;
    const brand = Color(0xFFD61A45);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget chipGrid(List<String> options, List<String> selectedList, String emptyMsg) {
              if (options.isEmpty) {
                return Text(emptyMsg, style: const TextStyle(color: Colors.black45, fontSize: 13));
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: options.map((item) {
                  final selected = selectedList.contains(item);
                  return FilterChip(
                    label: Text(item, style: const TextStyle(fontSize: 13)),
                    selected: selected,
                    onSelected: (v) {
                      setModalState(() {
                        if (v) {
                          if (!selectedList.contains(item)) selectedList.add(item);
                        } else {
                          selectedList.remove(item);
                        }
                      });
                    },
                    selectedColor: brand.withOpacity(0.2),
                    checkmarkColor: brand,
                  );
                }).toList(),
              );
            }

            final isHobbies = qIndex == 0;
            final title = isHobbies ? 'What are your hobbies?' : 'What are you interested in?';
            final selectedList = isHobbies ? localHobbies : localInterests;
            final canContinue = selectedList.length >= 3;

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.88,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Question ${qIndex + 1} of 2',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: brand)),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                      ],
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (qIndex + 1) / 2,
                        minHeight: 6,
                        backgroundColor: Colors.black12,
                        valueColor: const AlwaysStoppedAnimation(brand),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Column(
                            key: ValueKey(qIndex),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              const Text('Select at least 3.', style: TextStyle(color: Colors.black54, fontSize: 13)),
                              const SizedBox(height: 20),
                              chipGrid(
                                isHobbies ? _hobbyMasterOptions : _interestMasterOptions,
                                selectedList,
                                isHobbies
                                    ? 'No hobby options loaded. Check master_hobbies in Supabase.'
                                    : 'No interest options loaded. Check master_interests in Supabase.',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${selectedList.length} selected (min 3)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: selectedList.length < 3 ? Colors.orange : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (qIndex > 0)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setModalState(() => qIndex = 0),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Back'),
                            ),
                          ),
                        if (qIndex > 0) const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: !canContinue || _isLoadingData
                                ? null
                                : isHobbies
                                    ? () => setModalState(() => qIndex = 1)
                                    : () => _saveInterests(
                                          hobbies: localHobbies,
                                          interests: localInterests,
                                        ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: brand,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(isHobbies ? 'Next' : 'Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool readOnly = false, bool isNumber = false, int? maxLength, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        maxLength: maxLength,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          counterText: "",
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: readOnly,
          fillColor: readOnly ? Colors.black.withOpacity(0.04) : Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildDropdownField(String label, String? value, List<String> options, ValueChanged<String?> onChanged, {String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: (value != null && options.contains(value)) ? value : null,
        onChanged: onChanged,
        hint: Text('Select $label'),
        validator: validator ?? (val) {
          if (val == null || val.isEmpty) return '$label is required';
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: false,
        ),
        items: options.isEmpty 
          ? null 
          : options.map((opt) => DropdownMenuItem<String>(
              value: opt, 
              child: Text(opt, style: const TextStyle(color: Colors.black87)),
            )).toList(),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFD61A45))),
    );
  }

  /// One-question-at-a-time entry point for editing Basic Details. Reuses
  /// the same `_savePersonalDetails()` validation/save path as the
  /// all-fields editor below — this only changes how the answers are
  /// collected before that method runs.
  void _showBasicDetailsEditorQA() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return PersonalDetailsQASheet(
          name: _nameCtrl.text,
          dob: _dobCtrl.text,
          age: _ageCtrl.text,
          gender: _selectedGender,
          religion: _selectedReligion,
          createdBy: _selectedCreatedBy,
          physicalStatus: _selectedPhysicalStatus,
          height: _heightCtrl.text,
          weight: _weightCtrl.text,
          skinColor: _selectedSkinColor,
          bodyType: _selectedBodyType,
          maritalStatus: _selectedMaritalStatus,
          foodPreference: _selectedFoodPreference,
          languages: _selectedLanguages,
          about: _aboutCtrl.text,
          genderOptions: _genderOptions,
          religionOptions: _religionOptions,
          createdByOptions: _createdByOptions,
          physicalStatusOptions: _physicalStatusOptions,
          skinColorOptions: _skinColorOptions,
          bodyTypeOptions: _bodyTypeOptions,
          maritalStatusOptions: _maritalStatusOptions,
          foodPreferenceOptions: _foodPreferenceOptions,
          indianLanguages: _indianLanguages,
          internationalLanguages: _internationalLanguages,
          onSubmit: (values) {
            _nameCtrl.text = values['name'] as String;
            _dobCtrl.text = values['dob'] as String;
            _ageCtrl.text = values['age'] as String;
            _selectedGender = values['gender'] as String?;
            _selectedReligion = values['religion'] as String?;
            _selectedCreatedBy = values['createdBy'] as String?;
            _selectedPhysicalStatus = values['physicalStatus'] as String?;
            _heightCtrl.text = values['height'] as String;
            _weightCtrl.text = values['weight'] as String;
            _selectedSkinColor = values['skinColor'] as String?;
            _selectedBodyType = values['bodyType'] as String?;
            _selectedMaritalStatus = values['maritalStatus'] as String?;
            _selectedFoodPreference = values['foodPreference'] as String?;
            _selectedLanguages = List<String>.from(values['languages'] as List);
            _aboutCtrl.text = values['about'] as String;
            _savePersonalDetails();
          },
        );
      },
    );
  }

  void _showBasicDetailsEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                      const Text('Edit Basic Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle('Identity'),
                          _buildTextField('Full Name', _nameCtrl),
                          GestureDetector(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.tryParse(_dobCtrl.text) ?? DateTime.now().subtract(const Duration(days: 365 * 20)),
                                firstDate: DateTime.now().subtract(const Duration(days: 365 * 100)),
                                lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
                              );
                              if (picked != null) {
                                setModalState(() {
                                  _dobCtrl.text = picked.toIso8601String().split('T')[0];
                                  _calculateAge(picked);
                                });
                              }
                            },
                            child: AbsorbPointer(child: _buildTextField('Date of Birth', _dobCtrl, readOnly: true)),
                          ),
                          _buildTextField('Age', _ageCtrl, readOnly: true, isNumber: true),
                          _buildDropdownField('Gender', _selectedGender, _genderOptions, (val) => setModalState(() => _selectedGender = val)),
                          _buildDropdownField('Religion', _selectedReligion, _religionOptions, (val) => setModalState(() => _selectedReligion = val)),
                          _buildDropdownField('Profile Created By', _selectedCreatedBy, _createdByOptions, (val) => setModalState(() => _selectedCreatedBy = val)),
                          
                          _buildSectionTitle('Physical Attributes'),
                          _buildDropdownField('Physical Status', _selectedPhysicalStatus, _physicalStatusOptions, (val) => setModalState(() => _selectedPhysicalStatus = val)),
                          _buildTextField('Height (cm)', _heightCtrl, isNumber: true, maxLength: 3),
                          _buildTextField('Weight (kg)', _weightCtrl, isNumber: true, maxLength: 3),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: DropdownButtonFormField<String>(
                              value: _skinColorOptions.any((e) => e['value'] == _selectedSkinColor) ? _selectedSkinColor : null,
                              onChanged: (val) => setModalState(() => _selectedSkinColor = val),
                              decoration: InputDecoration(
                                labelText: 'Skin Color',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              items: _skinColorOptions.map((opt) {
                                final colorCode = opt['colour_code'] ?? '#000000';
                                final colorValue = int.parse(colorCode.replaceFirst('#', '0xFF'));
                                final color = Color(colorValue);
                                return DropdownMenuItem(
                                  value: opt['value'] as String,
                                  child: Row(
                                    children: [
                                      Container(width: 20, height: 20, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.black12))),
                                      const SizedBox(width: 12),
                                      Text(opt['value'] as String),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          _buildDropdownField('Body Type', _selectedBodyType, _bodyTypeOptions, (val) => setModalState(() => _selectedBodyType = val)),
                          
                          _buildSectionTitle('Preferences & Background'),
                          _buildDropdownField('Marital Status', _selectedMaritalStatus, _maritalStatusOptions, (val) => setModalState(() => _selectedMaritalStatus = val)),
                          _buildDropdownField('Food Preference', _selectedFoodPreference, _foodPreferenceOptions, (val) => setModalState(() => _selectedFoodPreference = val)),
                          
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8.0, top: 8.0),
                            child: Text('Languages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFD61A45))),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              ..._selectedLanguages.map((lang) => Chip(
                                label: Text(lang, style: const TextStyle(fontSize: 12)),
                                onDeleted: () => setModalState(() => _selectedLanguages.remove(lang)),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                backgroundColor: const Color(0xFFD61A45).withOpacity(0.1),
                              )),
                              ActionChip(
                                label: const Text('Add Language', style: TextStyle(fontSize: 12)),
                                onPressed: () async {
                                  final List<String> allLangs = [..._indianLanguages, ..._internationalLanguages];
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
                                  if (result != null && !_selectedLanguages.contains(result)) {
                                    setModalState(() => _selectedLanguages.add(result));
                                  }
                                },
                                avatar: const Icon(Icons.add, size: 14),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          
                          _buildSectionTitle('About Yourself'),
                          _buildTextField('Tell us about yourself...', _aboutCtrl, maxLines: 5, maxLength: 600),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Builder(
                              builder: (context) {
                                // Redraw character count on change
                                return Text(
                                  '${_aboutCtrl.text.length} / 600 ${_aboutCtrl.text.length < 100 ? "(min 100 chars required)" : ""}',
                                  style: TextStyle(fontSize: 12, color: _aboutCtrl.text.length < 100 ? Colors.orange : Colors.grey),
                                );
                              }
                            ),
                          ),
                          
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _savePersonalDetails,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD61A45),
                                padding: const EdgeInsets.all(16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: const Text('Save Details', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// One-question-at-a-time editor for Social Habits, mirroring
  /// manavizha/components/profile-steps/social-habits-qa.tsx (smoking,
  /// drinking, parties, pubs — all required). Same `_saveSocialHabits()`
  /// write path as before.
  void _showSocialHabitsEditor() {
    int qIndex = 0;
    const brand = Color(0xFFD61A45);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final questions = <({String title, String? value, List<String> options, void Function(String?) onChanged})>[
              (
                title: 'Do you smoke?',
                value: _selectedSmoking,
                options: _smokingOptions,
                onChanged: (val) => setModalState(() => _selectedSmoking = val),
              ),
              (
                title: 'Do you drink?',
                value: _selectedDrinking,
                options: _drinkingOptions,
                onChanged: (val) => setModalState(() => _selectedDrinking = val),
              ),
              (
                title: 'How do you feel about socializing / parties?',
                value: _selectedParties,
                options: _partiesOptions,
                onChanged: (val) => setModalState(() => _selectedParties = val),
              ),
              (
                title: 'What about entertainment / pubs?',
                value: _selectedPubs,
                options: _pubsOptions,
                onChanged: (val) => setModalState(() => _selectedPubs = val),
              ),
            ];
            final safeIndex = qIndex >= questions.length ? questions.length - 1 : qIndex;
            final q = questions[safeIndex];
            final isLast = safeIndex == questions.length - 1;
            final canContinue = (q.value?.trim() ?? '').isNotEmpty;

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.6,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Question ${safeIndex + 1} of ${questions.length}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: brand)),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                      ],
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (safeIndex + 1) / questions.length,
                        minHeight: 6,
                        backgroundColor: Colors.black12,
                        valueColor: const AlwaysStoppedAnimation(brand),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Column(
                            key: ValueKey(safeIndex),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(q.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 20),
                              DropdownButtonFormField<String>(
                                value: (q.value != null && q.options.contains(q.value)) ? q.value : null,
                                isExpanded: true,
                                hint: const Text('Select'),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                items: q.options
                                    .map((opt) => DropdownMenuItem<String>(
                                          value: opt,
                                          child: Text(opt, style: const TextStyle(color: Colors.black87)),
                                        ))
                                    .toList(),
                                onChanged: q.onChanged,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (safeIndex > 0)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setModalState(() => qIndex = safeIndex - 1),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Back'),
                            ),
                          ),
                        if (safeIndex > 0) const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: !canContinue || _isLoadingData
                                ? null
                                : isLast
                                    ? _saveSocialHabits
                                    : () => setModalState(() => qIndex = safeIndex + 1),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: brand,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(isLast ? 'Save' : 'Next'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        const SizedBox(height: 24),
        Center(
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F5),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD61A45).withOpacity(0.1), width: 4),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFD61A45).withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: ClipOval(
              child: _isLoadingPhoto 
                ? const Padding(
                    padding: EdgeInsets.all(30.0),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD61A45)),
                  )
                : _profilePhotoUrl != null 
                  ? Image.network(
                      _profilePhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 50, color: Color(0xFFD61A45)),
                    )
                  : const Icon(Icons.person, size: 50, color: Color(0xFFD61A45)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'My Profile',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Complete your profile categories below',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 32),
        _buildCategoryTile('Basic Details', Icons.info_outline),
        _buildCategoryTile('Contact Details', Icons.contact_phone_outlined),
        _buildCategoryTile('Educational Details', Icons.school_outlined),
        _buildCategoryTile('Professional Details', Icons.work_outline),
        _buildCategoryTile('Family Details', Icons.family_restroom_outlined),
        _buildCategoryTile('Horoscope Details', Icons.auto_awesome_outlined),
        _buildCategoryTile('Interests', Icons.sports_esports_outlined),
        _buildCategoryTile('Social Habits', Icons.local_cafe_outlined),
        Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.black.withOpacity(0.05)),
          ),
          child: ListTile(
            leading: const Icon(Icons.tune_outlined, color: Color(0xFFD61A45)),
            title: const Text('Partner Preferences', style: TextStyle(fontWeight: FontWeight.w600)),
            trailing: const Icon(Icons.chevron_right, color: Colors.black45),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PartnerPreferencesScreen()));
            },
          ),
        ),
        const SizedBox(height: 100), // spacing for bottom dock
      ],
    );
  }

  Widget _buildDataRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          Text(value != null && value.isNotEmpty ? value : 'Not set', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(String title, IconData icon) {
    bool isBasic = title == 'Basic Details';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withOpacity(0.05)),
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: const Color(0xFFD61A45)),
        title: Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
            _sectionPercentBadge(title),
          ],
        ),
        shape: const Border(), // Removes the default border lines upon expansion
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBasic) ...[
                  _buildDataRow('Name', _nameCtrl.text),
                  _buildDataRow('Gender', _selectedGender),
                  _buildDataRow('Age', _ageCtrl.text),
                  _buildDataRow('Height', _heightCtrl.text.isNotEmpty ? '${_heightCtrl.text} cm' : null),
                  _buildDataRow('Weight', _weightCtrl.text.isNotEmpty ? '${_weightCtrl.text} kg' : null),
                  _buildDataRow('Marital Status', _selectedMaritalStatus),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showBasicDetailsEditorQA,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit Details'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD61A45),
                        side: const BorderSide(color: Color(0xFFD61A45)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ] else if (title == 'Contact Details') ...[
                    _buildDataRow('Phone', _contactData?['phone']),
                    _buildDataRow('WhatsApp', _contactData?['whatsapp_number']),
                    _buildDataRow('Permanent City', _contactData?['permanent_district']),
                    _buildDataRow('Permanent State', _contactData?['permanent_state']),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            backgroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                            builder: (ctx) => const ContactDetailsQASheet(),
                          ).then((_) {
                            _fetchPersonalDetails();
                            _fetchSectionCompletion();
                          });
                        },
                        icon: const Icon(Icons.edit, size: 16, color: Color(0xFFD61A45)),
                        label: const Text('Edit Contact Details', style: TextStyle(color: Color(0xFFD61A45))),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFD61A45)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                ] else if (title == 'Interests') ...[
                  const Text(
                    'Hobbies',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.black45),
                  ),
                  const SizedBox(height: 8),
                  if (_selectedHobbies.isEmpty)
                    const Text('None selected', style: TextStyle(color: Colors.black54, fontSize: 13))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedHobbies
                          .map(
                            (h) => Chip(
                              label: Text(h, style: const TextStyle(fontSize: 12)),
                              backgroundColor: const Color(0xFFD61A45).withOpacity(0.1),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Interests',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.black45),
                  ),
                  const SizedBox(height: 8),
                  if (_selectedInterests.isEmpty)
                    const Text('None selected', style: TextStyle(color: Colors.black54, fontSize: 13))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _selectedInterests
                          .map(
                            (item) => Chip(
                              label: Text(item, style: const TextStyle(fontSize: 12)),
                              backgroundColor: const Color(0xFF2575FC).withOpacity(0.12),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showInterestsEditor,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit Interests'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD61A45),
                        side: const BorderSide(color: Color(0xFFD61A45)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ] else if (title == 'Social Habits') ...[
                  _buildDataRow('Smoking', _selectedSmoking),
                  _buildDataRow('Drinking', _selectedDrinking),
                  _buildDataRow('Parties', _selectedParties),
                  _buildDataRow('Pubs', _selectedPubs),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showSocialHabitsEditor,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit Social Habits'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD61A45),
                        side: const BorderSide(color: Color(0xFFD61A45)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ] else if (title == 'Educational Details') ...[
                  if (_educationRows.isEmpty)
                    const Text('No education entries yet', style: TextStyle(color: Colors.black54, fontSize: 13))
                  else
                    ..._educationRows.asMap().entries.map((e) {
                      final r = e.value;
                      final idx = e.key + 1;
                      final inst = r['institution']?.toString() ?? '';
                      final deg = r['degree']?.toString() ?? r['education']?.toString() ?? '';
                      final line = [deg, inst].where((s) => s.trim().isNotEmpty).join(' — ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$idx.', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                line.isEmpty ? 'Entry $idx' : line,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openEducationEditor,
                      icon: const Icon(Icons.edit, size: 16),
                      label: Text(_educationRows.isEmpty ? 'Add education' : 'Edit education'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD61A45),
                        side: const BorderSide(color: Color(0xFFD61A45)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ] else if (title == 'Professional Details') ...[
                  _buildDataRow(
                    'Type',
                    _professionType == 'none'
                        ? null
                        : _professionType == 'not_working'
                            ? 'Not Working'
                            : _professionType[0].toUpperCase() + _professionType.substring(1),
                  ),
                  if (_professionSummaryLine().isNotEmpty) _buildDataRow('Summary', _professionSummaryLine()),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openProfessionEditor,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit professional details'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD61A45),
                        side: const BorderSide(color: Color(0xFFD61A45)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ] else if (title == 'Family Details') ...[
                  _buildDataRow('Father', _familyMap['father_name']?.toString()),
                  _buildDataRow('Mother', _familyMap['mother_name']?.toString()),
                  _buildDataRow('Caste', _familyMap['caste']?.toString()),
                  _buildDataRow('Family type', _familyMap['family_type']?.toString()),
                  _buildDataRow('District', _familyMap['parents_district']?.toString()),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openFamilyEditor,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit family details'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD61A45),
                        side: const BorderSide(color: Color(0xFFD61A45)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ] else if (title == 'Horoscope Details') ...[
                  _buildDataRow('Star', _horoscopeMap['star']?.toString()),
                  _buildDataRow('Zodiac', _horoscopeMap['zodiac_sign']?.toString()),
                  _buildDataRow('Lagnam', _horoscopeMap['lagnam']?.toString()),
                  _buildDataRow('Time of birth', _horoscopeMap['time_of_birth']?.toString()),
                  _buildDataRow('Place of birth', _horoscopeMap['place_of_birth']?.toString()),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _openHoroscopeEditor,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit horoscope details'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD61A45),
                        side: const BorderSide(color: Color(0xFFD61A45)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ] else
                  const Text(
                    'Update details for category...',
                    style: TextStyle(color: Colors.black54),
                  ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class UserPhotosPage extends StatefulWidget {
  const UserPhotosPage({super.key});

  @override
  State<UserPhotosPage> createState() => _UserPhotosPageState();
}

class _UserPhotosPageState extends State<UserPhotosPage> {
  final ImagePicker _picker = ImagePicker();
  
  List<dynamic> profilePhotos = [];
  dynamic familyPhoto;
  dynamic aadharFront;
  dynamic aadharBack;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;

  final int maxFileSizeInBytes = 5 * 1024 * 1024; // 5 MB

  @override
  void initState() {
    super.initState();
    _fetchPhotos();
  }

  Future<void> _fetchPhotos() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      final data = await Supabase.instance.client
          .from('photos')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          profilePhotos = List<dynamic>.from(data['user_photos'] ?? []);
          familyPhoto = data['family_photo'];
          aadharFront = data['aadhar_front'];
          aadharBack = data['aadhar_back'];
        });
      }
    } catch (e) {
      debugPrint('Error fetching photos: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source, String category) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        final length = await pickedFile.length();
        if (length > maxFileSizeInBytes) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File exceeds 5MB size limit')));
          return;
        }
        setState(() {
          if (category == 'profile') {
            if (profilePhotos.length < 6) profilePhotos.add(pickedFile);
          } else if (category == 'family') {
            familyPhoto = pickedFile;
          } else if (category == 'aadhar_front') {
            aadharFront = pickedFile;
          } else if (category == 'aadhar_back') {
            aadharBack = pickedFile;
          }
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to pick image: $e')));
    }
  }

  void _showPickerOptions(String category) {
    if (category == 'profile' && profilePhotos.length >= 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max 6 profile photos allowed')));
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo Library'),
                onTap: () { Navigator.of(context).pop(); _pickImage(ImageSource.gallery, category); },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Camera'),
                onTap: () { Navigator.of(context).pop(); _pickImage(ImageSource.camera, category); },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildImageWidget(dynamic fileOrUrl, BoxFit fit) {
    if (fileOrUrl is String) {
      return Image.network(
        fileOrUrl, 
        fit: fit, 
        errorBuilder: (context, error, stackTrace) => Center(child: Icon(Icons.broken_image, color: Colors.black.withOpacity(0.3), size: 40)),
      );
    }
    if (fileOrUrl is XFile) {
      return Image.file(
        File(fileOrUrl.path), 
        fit: fit, 
        errorBuilder: (context, error, stackTrace) => Center(child: Icon(Icons.broken_image, color: Colors.black.withOpacity(0.3), size: 40)),
      );
    }
    return const SizedBox.shrink();
  }

  void _showImageViewer(dynamic fileOrUrl) {
    if (fileOrUrl == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (BuildContext context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.85,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8.0, top: 8.0),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 30),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 1.0,
                    maxScale: 4.0,
                    child: Center(
                      child: _buildImageWidget(fileOrUrl, BoxFit.contain),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(String title, VoidCallback onConfirm) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Remove Photo?'),
          content: Text('Are you sure you want to remove this $title?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      onConfirm();
    }
  }

  Widget _buildPhotoSlot(dynamic fileOrUrl, String label, String category, {double size = 100}) {
    if (!_isEditing && fileOrUrl == null) {
      return Container(
        width: size, height: size,
        decoration: BoxDecoration(color: const Color(0xFFF8F9FE), borderRadius: BorderRadius.circular(16)),
        child: const Center(child: Text('No File', style: TextStyle(color: Colors.black26, fontSize: 12))),
      );
    }
    return GestureDetector(
      onTap: _isEditing ? () => _showPickerOptions(category) : (fileOrUrl != null ? () => _showImageViewer(fileOrUrl) : null),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: fileOrUrl != null ? const Color(0xFFD61A45) : Colors.black12,
            width: 2,
            style: fileOrUrl != null ? BorderStyle.solid : BorderStyle.none,
          ),
        ),
        child: fileOrUrl == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add_a_photo, color: Colors.black45),
                  const SizedBox(height: 8),
                  Text(label, style: const TextStyle(fontSize: 10, color: Colors.black45, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _buildImageWidget(fileOrUrl, BoxFit.cover),
                  ),
                  if (_isEditing)
                    Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: () {
                          _confirmDelete(label.replaceAll('\n', ' ').toLowerCase(), () {
                            setState(() {
                              if (category == 'family') familyPhoto = null;
                              if (category == 'aadhar_front') aadharFront = null;
                              if (category == 'aadhar_back') aadharBack = null;
                            });
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildProfilePhotoSlot(int index) {
    if (index < profilePhotos.length) {
      final item = profilePhotos[index];
      return GestureDetector(
        onTap: _isEditing ? () => _showPickerOptions('profile') : () => _showImageViewer(item),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD61A45), width: 2),
            color: const Color(0xFFF0F0F5),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: _buildImageWidget(item, BoxFit.cover),
              ),
              if (_isEditing)
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () {
                      _confirmDelete('profile photo', () {
                        setState(() => profilePhotos.removeAt(index));
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close, color: Colors.white, size: 14),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    } else if (index == profilePhotos.length) {
      if (!_isEditing) return const SizedBox.shrink();
      return GestureDetector(
        onTap: () => _showPickerOptions('profile'),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12, width: 2),
          ),
          child: const Center(child: Icon(Icons.add_a_photo, color: Colors.black45, size: 28)),
        ),
      );
    } else {
      if (!_isEditing) return const SizedBox.shrink();
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F5).withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
        ),
      );
    }
  }

  Future<String> _processUpload(dynamic item, String bucket, String prefix) async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    if (item is String) return item; // It's already a Signed URL from DB
    if (item is XFile) {
      final ext = item.path.split('.').last.toLowerCase();
      final bytes = await item.readAsBytes();
      final path = '$userId/${prefix}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      
      String mimeType = 'image/jpeg';
      if (ext == 'png') mimeType = 'image/png';
      else if (ext == 'webp') mimeType = 'image/webp';

      await Supabase.instance.client.storage.from(bucket).uploadBinary(
        path, bytes, fileOptions: FileOptions(upsert: true, contentType: mimeType),
      );
      return await Supabase.instance.client.storage.from(bucket).createSignedUrl(path, 31536000);
    }
    throw Exception('Invalid image item variable');
  }

  Future<void> _savePhotos() async {
    if (profilePhotos.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please upload at least 3 profile photos')));
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);

    try {
      List<String> uploadedUserPhotos = [];
      for (int i = 0; i < profilePhotos.length; i++) {
        final url = await _processUpload(profilePhotos[i], 'user-photos', 'photo_${i + 1}');
        uploadedUserPhotos.add(url);
      }

      // Family photo is optional — only upload if a new one was selected,
      // otherwise preserve the existing URL from the database.
      String? familyUrl;
      if (familyPhoto != null) {
        familyUrl = await _processUpload(familyPhoto, 'family-photos', 'family');
      } else {
        // Keep existing value in DB (don't overwrite with null)
        final existing = await Supabase.instance.client
            .from('photos')
            .select('family_photo')
            .eq('user_id', userId)
            .maybeSingle();
        familyUrl = existing?['family_photo'] as String?;
      }
      // Aadhaar images are no longer collected — identity is verified via
      // DigiLocker (Settings → ID Verification), matching the web app.
      await Supabase.instance.client.from('photos').upsert({
        'user_id': userId,
        'user_photos': uploadedUserPhotos,
        'family_photo': familyUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photos saved successfully!')));
        setState(() => _isEditing = false); // Exit edit mode after successful save!
      }
    } catch (e) {
      debugPrint('Photo upload crash: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save photos: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Points members to Aadhaar verification via DigiLocker (Settings → ID
  /// Verification) — replaces the old Aadhaar card photo upload.
  Widget _digiLockerCard() {
    const brand = Color(0xFFD61A45);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: brand.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Verify your identity with Aadhaar through DigiLocker (Government of India). '
            'We never upload or store your Aadhaar card — only the result and the last 4 digits.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: brand),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MemberSettingsScreen(initialTab: 'verification')),
            ),
            icon: const Icon(Icons.verified_user_outlined, size: 18),
            label: const Text('Verify with DigiLocker'),
          ),
        ],
      ),
    );
  }

  /// One-question-at-a-time editor, mirroring
  /// manavizha/components/profile-steps/photos-qa.tsx: photos (min 3),
  /// family photo (optional), Aadhar front, Aadhar back. Same
  /// `_savePhotos()` validation and upload path as before.
  int _qIndex = 0;

  Widget _buildQAEditor() {
    const brand = Color(0xFFD61A45);
    final questions = <({String title, String subtitle, bool Function() isValid, Widget child})>[
      (
        title: 'Add your photos',
        subtitle: '${profilePhotos.length} / 6 uploaded · minimum 3 required · max 5MB each. '
            'The first photo acts as your display picture.',
        isValid: () => profilePhotos.length >= 3,
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 6,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) => _buildProfilePhotoSlot(index),
        ),
      ),
      (
        title: 'Have a family photo to share?',
        subtitle: 'Optional. Max 5MB.',
        isValid: () => true,
        child: Align(
          alignment: Alignment.centerLeft,
          child: _buildPhotoSlot(familyPhoto, 'Family\nPhoto', 'family', size: 140),
        ),
      ),
      (
        title: 'Get your ID Verified badge',
        subtitle: 'Optional. Verify with Aadhaar through DigiLocker — no card photos are uploaded.',
        isValid: () => true,
        child: _digiLockerCard(),
      ),
    ];
    final safeIndex = _qIndex >= questions.length ? questions.length - 1 : _qIndex;
    final q = questions[safeIndex];
    final isLast = safeIndex == questions.length - 1;
    final canContinue = q.isValid();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Question ${safeIndex + 1} of ${questions.length}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: brand)),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.redAccent),
                onPressed: () {
                  // Abort editing: refetch to reset local un-verified edits.
                  setState(() {
                    _isEditing = false;
                    _isLoading = true;
                  });
                  _fetchPhotos();
                },
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (safeIndex + 1) / questions.length,
              minHeight: 6,
              backgroundColor: Colors.black12,
              valueColor: const AlwaysStoppedAnimation(brand),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Column(
                  key: ValueKey(safeIndex),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(q.subtitle, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                    const SizedBox(height: 20),
                    q.child,
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (safeIndex > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSaving ? null : () => setState(() => _qIndex = safeIndex - 1),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Back'),
                  ),
                ),
              if (safeIndex > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: !canContinue || _isSaving
                      ? null
                      : isLast
                          ? _savePhotos
                          : () => setState(() => _qIndex = safeIndex + 1),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(isLast ? 'Verify & Save Uploads' : 'Next'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFD61A45)));
    }

    if (_isEditing) return _buildQAEditor();

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Your Gallery', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFD61A45))),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.black54),
              onPressed: () => setState(() {
                _isEditing = true;
                _qIndex = 0;
              }),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Profile Photos (3 to 6)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Max 5MB each. The first photo acts as your display picture.', style: TextStyle(color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: profilePhotos.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            return _buildProfilePhotoSlot(index);
          },
        ),

        const SizedBox(height: 32),
        const Text('Family Photo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Optional. Max 5MB.', style: TextStyle(color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: _buildPhotoSlot(familyPhoto, 'Family\nPhoto', 'family', size: 120),
        ),

        const SizedBox(height: 32),
        const Text('ID Verification', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _digiLockerCard(),
        const SizedBox(height: 100), // Spacing for bottom dock
      ],
    );
  }
}

class ReferralDetailsPage extends StatefulWidget {
  const ReferralDetailsPage({super.key});

  @override
  State<ReferralDetailsPage> createState() => _ReferralDetailsPageState();
}

class _ReferralDetailsPageState extends State<ReferralDetailsPage> {
  final TextEditingController _partnerIdCtrl = TextEditingController();

  // State
  String _partnerName = '';
  String _partnerError = '';
  bool _isLoadingPartner = false;
  bool _isSaving = false;
  bool _isLoading = true;
  String _lastFetchedId = '';

  // Debounce timer
  Future<void>? _debounce;

  // Pattern: 2 uppercase letters, 4 digits, 2 uppercase letters, 3 digits
  final RegExp _partnerIdPattern = RegExp(r'^[A-Z]{2}\d{4}[A-Z]{2}\d{3}$');

  @override
  void initState() {
    super.initState();
    _loadSavedReferral();
    _partnerIdCtrl.addListener(_onPartnerIdChanged);
  }

  @override
  void dispose() {
    _partnerIdCtrl.removeListener(_onPartnerIdChanged);
    _partnerIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedReferral() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final data = await Supabase.instance.client
          .from('referral_details')
          .select('referral_partner_id, referral_partner_name')
          .eq('user_id', userId)
          .maybeSingle();
      if (mounted && data != null) {
        final savedId = (data['referral_partner_id'] as String?) ?? '';
        final savedName = (data['referral_partner_name'] as String?) ?? '';
        _partnerIdCtrl.text = savedId;
        if (savedId.isNotEmpty) {
          setState(() {
            _partnerName = savedName;
            _lastFetchedId = savedId;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading referral details: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onPartnerIdChanged() {
    // Enforce uppercase alphanumeric, max 11 chars
    final raw = _partnerIdCtrl.text;
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final limited = cleaned.length > 11 ? cleaned.substring(0, 11) : cleaned;
    if (limited != raw) {
      _partnerIdCtrl.value = _partnerIdCtrl.value.copyWith(
        text: limited,
        selection: TextSelection.collapsed(offset: limited.length),
      );
      return;
    }

    // Reset display state if ID changed
    if (limited != _lastFetchedId) {
      setState(() {
        _partnerName = '';
        _partnerError = '';
      });
    }

    // Debounce lookup by 500ms
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _partnerIdCtrl.text == limited) {
        _fetchPartnerName(limited);
      }
    });
  }

  Future<void> _fetchPartnerName(String partnerId) async {
    if (partnerId.isEmpty) {
      if (mounted) setState(() { _partnerName = ''; _partnerError = ''; _lastFetchedId = ''; });
      return;
    }

    // Already fetched for this ID
    if (partnerId == _lastFetchedId && (partnerId.length == 11) && (_partnerName.isNotEmpty || _partnerError.isNotEmpty)) return;

    if (!_partnerIdPattern.hasMatch(partnerId)) {
      if (mounted) setState(() { _partnerName = ''; _partnerError = ''; _lastFetchedId = ''; });
      return;
    }

    if (mounted) setState(() { _isLoadingPartner = true; _lastFetchedId = partnerId; });

    try {
      final data = await Supabase.instance.client
          .from('referral_partners')
          .select('name, partner_id')
          .eq('partner_id', partnerId)
          .maybeSingle();

      if (!mounted) return;

      if (data != null) {
        setState(() {
          _partnerName = (data['name'] as String?) ?? 'Partner found';
          _partnerError = '';
        });
      } else {
        setState(() {
          _partnerName = '';
          _partnerError = 'This partner ID is not valid. Please get the proper ID from the partner.';
        });
      }
    } catch (e) {
      if (mounted) setState(() { _partnerError = 'Error looking up partner. Please try again.'; });
    } finally {
      if (mounted) setState(() => _isLoadingPartner = false);
    }
  }

  Future<void> _saveReferral() async {
    final partnerId = _partnerIdCtrl.text.trim();

    // Validate pattern if filled
    if (partnerId.isNotEmpty && !_partnerIdPattern.hasMatch(partnerId)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Invalid ID format: 2 letters, 4 numbers, 2 letters, 3 numbers (e.g. AB1234CD567)'),
      ));
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client.from('referral_details').upsert({
        'user_id': userId,
        'referral_partner_id': partnerId.isEmpty ? null : partnerId,
        'referral_partner_name': _partnerName.isEmpty ? null : _partnerName,
      }, onConflict: 'user_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Referral details saved successfully!'),
          backgroundColor: Color(0xFFD61A45),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool get _isValidPattern => _partnerIdPattern.hasMatch(_partnerIdCtrl.text);

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFD61A45)));
    }

    // Single-question presentation, mirroring
    // manavizha/components/profile-steps/referral-qa.tsx — there's only one
    // real field here, entirely optional. Same lookup and save path as before.
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text('Question 1 of 1',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD61A45))),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: const LinearProgressIndicator(
            value: 1,
            minHeight: 6,
            backgroundColor: Colors.black12,
            valueColor: AlwaysStoppedAnimation(Color(0xFFD61A45)),
          ),
        ),
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text('Were you referred by a partner?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            'Optional — you can skip this step. Enter the referral partner ID if you have one.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ),
        // ── Input card ───────────────────────────────────────────────────
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.black.withOpacity(0.06)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Referral Partner ID ───────────────────────────────────
                const Text('REFERRAL PARTNER ID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54, letterSpacing: 0.8)),
                const SizedBox(height: 6),
                TextField(
                  controller: _partnerIdCtrl,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 11,
                  decoration: InputDecoration(
                    hintText: 'E.G., AB1234CD567',
                    counterText: '',
                    filled: true,
                    fillColor: _isValidPattern && _partnerName.isNotEmpty
                        ? const Color(0xFFE8F5F1)
                        : _partnerError.isNotEmpty
                            ? const Color(0xFFFFF0F0)
                            : const Color(0xFFF8F8F8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.black.withOpacity(0.1))),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: _isValidPattern && _partnerName.isNotEmpty
                            ? const Color(0xFFD61A45).withOpacity(0.4)
                            : _partnerError.isNotEmpty
                                ? Colors.red.withOpacity(0.4)
                                : Colors.black.withOpacity(0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFD61A45)),
                    ),
                    suffixIcon: _isLoadingPartner
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD61A45))),
                          )
                        : null,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.5),
                ),
                const SizedBox(height: 4),
                if (!_isValidPattern && _partnerIdCtrl.text.isNotEmpty)
                  const Text('Format: 2 letters, 4 numbers, 2 letters, 3 numbers',
                      style: TextStyle(fontSize: 11, color: Colors.orange)),
                if (_isValidPattern && _partnerName.isNotEmpty && _partnerError.isEmpty)
                  const Text('ID verified ✓', style: TextStyle(fontSize: 11, color: Color(0xFFD61A45), fontWeight: FontWeight.w600)),
                const Text('Enter the ID of your referral partner (optional)',
                    style: TextStyle(fontSize: 11, color: Colors.black45)),

                const SizedBox(height: 20),
                const Divider(height: 1, color: Color(0xFFF0EBE3)),
                const SizedBox(height: 20),

                // ── Partner Name ──────────────────────────────────────────
                const Text('PARTNER NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54, letterSpacing: 0.8)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: _partnerName.isNotEmpty
                        ? const Color(0xFFF8FDFB)
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _partnerName.isNotEmpty
                          ? const Color(0xFFD61A45).withOpacity(0.3)
                          : Colors.black.withOpacity(0.08),
                    ),
                  ),
                  child: Text(
                    _isLoadingPartner
                        ? 'Finding partner...'
                        : _partnerError.isNotEmpty
                            ? _partnerError
                            : _partnerName.isNotEmpty
                                ? _partnerName
                                : 'Waiting for ID...',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: _partnerName.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                      color: _partnerError.isNotEmpty
                          ? Colors.red.shade700
                          : _partnerName.isNotEmpty
                              ? const Color(0xFF1F4068)
                              : Colors.black38,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // ── Save button ───────────────────────────────────────────────────
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveReferral,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD61A45),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isSaving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),

        const SizedBox(height: 16),

        // ── Skip note ─────────────────────────────────────────────────────
        const Center(
          child: Text('Referral partner is optional — you can skip this step.',
              style: TextStyle(fontSize: 12, color: Colors.black38)),
        ),
        const SizedBox(height: 100),
      ],
    );
  }
}


class ContactDetailsPage extends StatefulWidget {
  const ContactDetailsPage({super.key});

  @override
  State<ContactDetailsPage> createState() => _ContactDetailsPageState();
}

class _ContactDetailsPageState extends State<ContactDetailsPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final data = await Supabase.instance.client.from('contact_details').select().eq('user_id', userId).maybeSingle();
      if (mounted) setState(() { _userData = data; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildDisplayRow(String label, String? value) {
    String displayValue = (value == null || value.trim().isEmpty) ? 'Not Provided' : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13))),
          Expanded(flex: 3, child: Text(displayValue, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, List<Widget> children, IconData icon) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.black.withOpacity(0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFFD61A45), size: 20),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  void _openEditor() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => ContactDetailsEditorSheet(initialData: _userData),
    );
    _fetchData(); // After it closes, refetch to show new results!
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFFD61A45)));

    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text('Contact Details', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFD61A45))),
                   SizedBox(height: 4),
                   Text('Your active communication lines', style: TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_note, color: Color(0xFFD61A45), size: 30),
              style: IconButton.styleFrom(backgroundColor: const Color(0xFFD61A45).withOpacity(0.1)),
              onPressed: _openEditor,
            ),
          ],
        ),
        const SizedBox(height: 32),

        _buildSummaryCard(
          'Communication',
          [
            _buildDisplayRow('Phone Number', _userData?['phone']),
            _buildDisplayRow('WhatsApp Number', _userData?['whatsapp_number']),
          ],
          Icons.phone_iphone,
        ),

        _buildSummaryCard(
          'Permanent Address',
          [
            _buildDisplayRow('Line 1', _userData?['permanent_address_line1']),
            _buildDisplayRow('Line 2', _userData?['permanent_address_line2']),
            _buildDisplayRow('Pincode', _userData?['permanent_pincode']),
            _buildDisplayRow('Area', _userData?['permanent_area']),
            _buildDisplayRow('Taluk / Tehsil', _userData?['permanent_taluk']),
            _buildDisplayRow('District', _userData?['permanent_district']),
            _buildDisplayRow('Division', _userData?['permanent_division']),
            _buildDisplayRow('State', _userData?['permanent_state']),
            _buildDisplayRow('Country', _userData?['permanent_country']),
            _buildDisplayRow('Landmark', _userData?['permanent_landmark']),
          ],
          Icons.home_outlined,
        ),

        _buildSummaryCard(
          'Current Address',
          [
            _buildDisplayRow('Line 1', _userData?['current_address_line1']),
            _buildDisplayRow('Line 2', _userData?['current_address_line2']),
            _buildDisplayRow('Pincode', _userData?['current_pincode']),
            _buildDisplayRow('Area', _userData?['current_area']),
            _buildDisplayRow('Taluk / Tehsil', _userData?['current_taluk']),
            _buildDisplayRow('District', _userData?['current_district']),
            _buildDisplayRow('Division', _userData?['current_division']),
            _buildDisplayRow('State', _userData?['current_state']),
            _buildDisplayRow('Country', _userData?['current_country']),
            _buildDisplayRow('Landmark', _userData?['current_landmark']),
          ],
          Icons.location_on_outlined,
        ),
        const SizedBox(height: 100),
      ],
    );
  }
}

class ContactDetailsEditorSheet extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const ContactDetailsEditorSheet({super.key, this.initialData});

  @override
  State<ContactDetailsEditorSheet> createState() => _ContactDetailsEditorSheetState();
}

class _ContactDetailsEditorSheetState extends State<ContactDetailsEditorSheet> with ContactDetailsLogic {
  @override
  void initState() {
    super.initState();
    initContactDetailsLogic();
  }

  @override
  void dispose() {
    disposeContactDetailsLogic();
    super.dispose();
  }

  void _showAreaPicker(bool isPermanent) {
    if ((isPermanent && permAreasList.isEmpty) || (!isPermanent && currAreasList.isEmpty)) return;
    if (!isPermanent && sameAsPerm) return;

    final list = isPermanent ? permAreasList : currAreasList;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Select Area', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (ctx, i) {
                    return ListTile(
                      leading: const Icon(Icons.location_on_outlined, color: Color(0xFFD61A45)),
                      title: Text(list[i]['Name']),
                      onTap: () {
                        Navigator.pop(ctx);
                        selectArea(list[i], isPermanent);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool readOnly = false, bool isNumber = false, int? maxLength}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        maxLength: maxLength,
        decoration: InputDecoration(
          labelText: label,
          counterText: "",
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: readOnly,
          fillColor: readOnly ? Colors.black.withOpacity(0.04) : Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildAreaDropdown(String label, String value, bool isPermanent, bool isLoading) {
    bool disabled = !isPermanent && sameAsPerm;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => _showAreaPicker(isPermanent),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black45),
            borderRadius: BorderRadius.circular(12),
            color: disabled ? Colors.black.withOpacity(0.04) : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(value.isEmpty ? label : value, style: TextStyle(fontSize: 16, color: value.isEmpty ? Colors.black54 : Colors.black87)),
              if (isLoading)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
                const Icon(Icons.arrow_drop_down, color: Colors.black54),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double modalHeight = MediaQuery.of(context).size.height * 0.75;

    if (isLoadingData) {
      return SizedBox(
        height: modalHeight,
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFFD61A45)),
        ),
      );
    }

    return SizedBox(
      height: modalHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Edit Contacts', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFD61A45))),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Fill out your communication lines and exact addresses.', style: TextStyle(color: Colors.black54)),
                const Divider(height: 32),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              children: [
                _buildTextField('Phone Number', phoneCtrl, isNumber: true, maxLength: 13),
        Row(
          children: [
            Checkbox(
              value: sameAsPhone,
              activeColor: const Color(0xFFD61A45),
              onChanged: (val) {
                setState(() {
                  sameAsPhone = val ?? false;
                  if (sameAsPhone) {
                    whatsappCtrl.text = phoneCtrl.text;
                  } else {
                    whatsappCtrl.text = '+91 ';
                  }
                });
              },
            ),
            const Text('WhatsApp same as Phone Number'),
          ],
        ),
        if (!sameAsPhone)
          _buildTextField('WhatsApp Number', whatsappCtrl, isNumber: true, maxLength: 13),

        const Divider(height: 48),
        const Text('Permanent Address', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildTextField('Address Line 1', permLine1Ctrl),
        _buildTextField('Address Line 2 (Optional)', permLine2Ctrl),
        _buildTextField('Pincode (6 Digits)', permPincodeCtrl, isNumber: true, maxLength: 6),
        _buildAreaDropdown('Select Area / Post Office', permArea, true, isLoadingPerm),
        _buildTextField('Taluk / Tehsil', permTalukCtrl, readOnly: true),
        _buildTextField('District', permDistrictCtrl, readOnly: true),
        _buildTextField('Division', permDivisionCtrl, readOnly: true),
        _buildTextField('Region / Circle', permRegionCtrl, readOnly: true),
        _buildTextField('State', permStateCtrl, readOnly: true),
        _buildTextField('Country', permCountryCtrl, readOnly: true),
        _buildTextField('Landmark (Optional)', permLandmarkCtrl),

        const Divider(height: 48),
        const Text('Current Address', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          children: [
            Checkbox(
              value: sameAsPerm,
              activeColor: const Color(0xFFD61A45),
              onChanged: (val) {
                setState(() {
                  sameAsPerm = val ?? false;
                  syncPermToCurr();
                });
              },
            ),
            const Text('Same as Permanent Address'),
          ],
        ),
        const SizedBox(height: 16),
        if (!sameAsPerm) ...[
          _buildTextField('Address Line 1', currLine1Ctrl),
          _buildTextField('Address Line 2 (Optional)', currLine2Ctrl),
          _buildTextField('Pincode (6 Digits)', currPincodeCtrl, isNumber: true, maxLength: 6),
          _buildAreaDropdown('Select Area / Post Office', currArea, false, isLoadingCurr),
          _buildTextField('Taluk / Tehsil', currTalukCtrl, readOnly: true),
          _buildTextField('District', currDistrictCtrl, readOnly: true),
          _buildTextField('Division', currDivisionCtrl, readOnly: true),
          _buildTextField('Region / Circle', currRegionCtrl, readOnly: true),
          _buildTextField('State', currStateCtrl, readOnly: true),
          _buildTextField('Country', currCountryCtrl, readOnly: true),
          _buildTextField('Landmark (Optional)', currLandmarkCtrl),
        ],

        const SizedBox(height: 32),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: () => saveUserData(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD61A45),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('Save Content Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 100), // spacing for bottom dock
              ],
            ),
          ),
        ],
      ),
    );
  }
}
