import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'profile_extended_details.dart';
import 'user_profile_completion.dart';

class UserDetailsPage extends StatefulWidget {
  const UserDetailsPage({super.key});

  @override
  State<UserDetailsPage> createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage> {
  String? _profilePhotoUrl;
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
  String? _selectedCreatedBy;
  String? _selectedPhysicalStatus;
  String? _selectedSkinColor;
  String? _selectedBodyType;
  String? _selectedMaritalStatus;
  String? _selectedFoodPreference;
  List<String> _selectedLanguages = [];

  // Master Data Lists
  List<String> _genderOptions = ['Male', 'Female'];
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
        : (p > 0 ? const Color(0xFF6A11CB) : const Color(0xFF737373));
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
    showEducationDetailsSheet(
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
      default:
        return 'Private';
    }
  }

  void _openProfessionEditor() {
    showProfessionDetailsSheet(
      context,
      initialEmploymentType: _employmentLabel,
      emp: Map<String, dynamic>.from(_empProf),
      bus: Map<String, dynamic>.from(_busProf),
      stu: Map<String, dynamic>.from(_stuProf),
      onSaved: (category, employmentLabel, emp, bus, stu) {
        final pct = computeProfessionSectionPercentForType(category, emp, bus, stu);
        if (mounted) {
          setState(() {
            _employmentLabel = employmentLabel;
            _professionType = category;
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
    showFamilyDetailsSheet(
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
    showHoroscopeDetailsSheet(
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

      if (data != null && mounted) {
        setState(() {
          _nameCtrl.text = data['name'] ?? '';
          _dobCtrl.text = data['date_of_birth'] ?? '';
          _ageCtrl.text = data['age']?.toString() ?? '';
          _heightCtrl.text = data['height']?.toString() ?? '';
          _weightCtrl.text = data['weight']?.toString() ?? '';
          _aboutCtrl.text = data['about'] ?? '';
          _selectedGender = data['sex'];
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

  final _socialFormKey = GlobalKey<FormState>();

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
    if (!(_socialFormKey.currentState?.validate() ?? false)) {
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

  void _showInterestsEditor() {
    List<String> localHobbies = List<String>.from(_selectedHobbies);
    List<String> localInterests = List<String>.from(_selectedInterests);

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
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.88,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Edit Interests',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const Text(
                      'Choose at least 3 hobbies and 3 interests (same as web profile setup).',
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const Divider(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionTitle('Hobbies'),
                            if (_hobbyMasterOptions.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: Text(
                                  'No hobby options loaded. Check master_hobbies in Supabase.',
                                  style: TextStyle(color: Colors.black45, fontSize: 13),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _hobbyMasterOptions.map((h) {
                                  final selected = localHobbies.contains(h);
                                  return FilterChip(
                                    label: Text(h, style: const TextStyle(fontSize: 13)),
                                    selected: selected,
                                    onSelected: (v) {
                                      setModalState(() {
                                        if (v) {
                                          if (!localHobbies.contains(h)) localHobbies.add(h);
                                        } else {
                                          localHobbies.remove(h);
                                        }
                                      });
                                    },
                                    selectedColor: const Color(0xFF6A11CB).withOpacity(0.2),
                                    checkmarkColor: const Color(0xFF6A11CB),
                                  );
                                }).toList(),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              '${localHobbies.length} selected (min 3)',
                              style: TextStyle(
                                fontSize: 12,
                                color: localHobbies.length < 3 ? Colors.orange : Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _buildSectionTitle('Interests'),
                            if (_interestMasterOptions.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 16),
                                child: Text(
                                  'No interest options loaded. Check master_interests in Supabase.',
                                  style: TextStyle(color: Colors.black45, fontSize: 13),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _interestMasterOptions.map((item) {
                                  final selected = localInterests.contains(item);
                                  return FilterChip(
                                    label: Text(item, style: const TextStyle(fontSize: 13)),
                                    selected: selected,
                                    onSelected: (v) {
                                      setModalState(() {
                                        if (v) {
                                          if (!localInterests.contains(item)) localInterests.add(item);
                                        } else {
                                          localInterests.remove(item);
                                        }
                                      });
                                    },
                                    selectedColor: const Color(0xFF6A11CB).withOpacity(0.2),
                                    checkmarkColor: const Color(0xFF6A11CB),
                                  );
                                }).toList(),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              '${localInterests.length} selected (min 3)',
                              style: TextStyle(
                                fontSize: 12,
                                color: localInterests.length < 3 ? Colors.orange : Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isLoadingData
                                    ? null
                                    : () => _saveInterests(
                                          hobbies: localHobbies,
                                          interests: localInterests,
                                        ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6A11CB),
                                  padding: const EdgeInsets.all(16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Save Interests',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF6A11CB))),
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
                            child: Text('Languages', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF6A11CB))),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              ..._selectedLanguages.map((lang) => Chip(
                                label: Text(lang, style: const TextStyle(fontSize: 12)),
                                onDeleted: () => setModalState(() => _selectedLanguages.remove(lang)),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                backgroundColor: const Color(0xFF6A11CB).withOpacity(0.1),
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
                                backgroundColor: const Color(0xFF6A11CB),
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

  void _showSocialHabitsEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.6,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Edit Social Habits', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: Form(
                      key: _socialFormKey,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 40, top: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDropdownField('Smoking', _selectedSmoking, _smokingOptions, (val) => setModalState(() => _selectedSmoking = val)),
                            _buildDropdownField('Drinking', _selectedDrinking, _drinkingOptions, (val) => setModalState(() => _selectedDrinking = val)),
                            _buildDropdownField('Parties', _selectedParties, _partiesOptions, (val) => setModalState(() => _selectedParties = val)),
                            _buildDropdownField('Pubs', _selectedPubs, _pubsOptions, (val) => setModalState(() => _selectedPubs = val)),
                            
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _saveSocialHabits,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6A11CB),
                                  padding: const EdgeInsets.all(16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: const Text('Save Social Habits', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
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
              border: Border.all(color: const Color(0xFF6A11CB).withOpacity(0.1), width: 4),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6A11CB).withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: ClipOval(
              child: _isLoadingPhoto 
                ? const Padding(
                    padding: EdgeInsets.all(30.0),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6A11CB)),
                  )
                : _profilePhotoUrl != null 
                  ? Image.network(
                      _profilePhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 50, color: Color(0xFF6A11CB)),
                    )
                  : const Icon(Icons.person, size: 50, color: Color(0xFF6A11CB)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'User Details',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Complete your profile categories below',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 32),
        _buildCategoryTile('Basic Details', Icons.info_outline),
        _buildCategoryTile('Educational Details', Icons.school_outlined),
        _buildCategoryTile('Professional Details', Icons.work_outline),
        _buildCategoryTile('Family Details', Icons.family_restroom_outlined),
        _buildCategoryTile('Horoscope Details', Icons.auto_awesome_outlined),
        _buildCategoryTile('Interests', Icons.sports_esports_outlined),
        _buildCategoryTile('Social Habits', Icons.local_cafe_outlined),
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
        leading: Icon(icon, color: const Color(0xFF6A11CB)),
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
                      onPressed: _showBasicDetailsEditor,
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit Details'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6A11CB),
                        side: const BorderSide(color: Color(0xFF6A11CB)),
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
                              backgroundColor: const Color(0xFF6A11CB).withOpacity(0.1),
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
                        foregroundColor: const Color(0xFF6A11CB),
                        side: const BorderSide(color: Color(0xFF6A11CB)),
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
                        foregroundColor: const Color(0xFF6A11CB),
                        side: const BorderSide(color: Color(0xFF6A11CB)),
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
                        foregroundColor: const Color(0xFF6A11CB),
                        side: const BorderSide(color: Color(0xFF6A11CB)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ] else if (title == 'Professional Details') ...[
                  _buildDataRow(
                    'Type',
                    _professionType == 'none'
                        ? null
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
                        foregroundColor: const Color(0xFF6A11CB),
                        side: const BorderSide(color: Color(0xFF6A11CB)),
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
                        foregroundColor: const Color(0xFF6A11CB),
                        side: const BorderSide(color: Color(0xFF6A11CB)),
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
                        foregroundColor: const Color(0xFF6A11CB),
                        side: const BorderSide(color: Color(0xFF6A11CB)),
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
            color: fileOrUrl != null ? const Color(0xFF6A11CB) : Colors.black12,
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
            border: Border.all(color: const Color(0xFF6A11CB), width: 2),
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
    if (familyPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Family photo is mandatory')));
      return;
    }
    if (aadharFront == null || aadharBack == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aadhar Front & Back are mandatory')));
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

      final familyUrl = await _processUpload(familyPhoto, 'family-photos', 'family');
      final aadharFrontUrl = await _processUpload(aadharFront, 'aadhar-photos', 'front');
      final aadharBackUrl = await _processUpload(aadharBack, 'aadhar-photos', 'back');

      await Supabase.instance.client.from('photos').upsert({
        'user_id': userId,
        'user_photos': uploadedUserPhotos,
        'family_photo': familyUrl,
        'aadhar_front': aadharFrontUrl,
        'aadhar_back': aadharBackUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photos verified and saved successfully!')));
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF6A11CB)));
    }

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Your Gallery', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF6A11CB))),
            IconButton(
              icon: Icon(_isEditing ? Icons.close : Icons.edit, color: _isEditing ? Colors.redAccent : Colors.black54),
              onPressed: () {
                setState(() {
                  _isEditing = !_isEditing;
                  // Refetch to reset local un-verified edits if they abort!
                  if (!_isEditing) {
                     setState(() => _isLoading = true);
                     _fetchPhotos();
                  }
                });
              },
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
          itemCount: _isEditing ? 6 : profilePhotos.length,
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
        const Text('Mandatory. Max 5MB.', style: TextStyle(color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: _buildPhotoSlot(familyPhoto, 'Family\nPhoto', 'family', size: 120),
        ),

        const SizedBox(height: 32),
        const Text('Aadhar Card', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Mandatory. Front and back sides required for KYC.', style: TextStyle(color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildPhotoSlot(aadharFront, 'Aadhar\nFront', 'aadhar_front', size: 120)),
            const SizedBox(width: 16),
            Expanded(child: _buildPhotoSlot(aadharBack, 'Aadhar\nBack', 'aadhar_back', size: 120)),
          ],
        ),

        if (_isEditing) ...[
          const SizedBox(height: 48),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _savePhotos,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6A11CB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isSaving 
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Verify & Save Uploads', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
        const SizedBox(height: 100), // Spacing for bottom dock
      ],
    );
  }
}

class ReferralDetailsPage extends StatelessWidget {
  const ReferralDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.card_giftcard_outlined, size: 80, color: Color(0xFF6A11CB)),
          SizedBox(height: 16),
          Text('Referral Details', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text('Track your referrals and rewards', style: TextStyle(color: Colors.black54)),
        ],
      ),
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
                Icon(icon, color: const Color(0xFF6A11CB), size: 20),
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
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF6A11CB)));

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
                   Text('Contact Details', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF6A11CB))),
                   SizedBox(height: 4),
                   Text('Your active communication lines', style: TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_note, color: Color(0xFF6A11CB), size: 30),
              style: IconButton.styleFrom(backgroundColor: const Color(0xFF6A11CB).withOpacity(0.1)),
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

class _ContactDetailsEditorSheetState extends State<ContactDetailsEditorSheet> {
  bool _isLoadingData = true;

  final _phoneCtrl = TextEditingController(text: '+91');
  final _whatsappCtrl = TextEditingController(text: '+91');
  bool _sameAsPhone = false;

  final _permLine1Ctrl = TextEditingController();
  final _permLine2Ctrl = TextEditingController();
  final _permPincodeCtrl = TextEditingController();
  final _permTalukCtrl = TextEditingController();
  final _permDistrictCtrl = TextEditingController();
  final _permDivisionCtrl = TextEditingController();
  final _permRegionCtrl = TextEditingController();
  final _permStateCtrl = TextEditingController();
  final _permCountryCtrl = TextEditingController();
  final _permLandmarkCtrl = TextEditingController();
  String _permArea = '';
  List<dynamic> _permAreasList = [];
  bool _isLoadingPerm = false;

  bool _sameAsPerm = false;

  final _currLine1Ctrl = TextEditingController();
  final _currLine2Ctrl = TextEditingController();
  final _currPincodeCtrl = TextEditingController();
  final _currTalukCtrl = TextEditingController();
  final _currDistrictCtrl = TextEditingController();
  final _currDivisionCtrl = TextEditingController();
  final _currRegionCtrl = TextEditingController();
  final _currStateCtrl = TextEditingController();
  final _currCountryCtrl = TextEditingController();
  final _currLandmarkCtrl = TextEditingController();
  String _currArea = '';
  List<dynamic> _currAreasList = [];
  bool _isLoadingCurr = false;

  @override
  void initState() {
    super.initState();
    _fetchUserData();

    _phoneCtrl.addListener(() {
      if (_sameAsPhone) {
        _whatsappCtrl.text = _phoneCtrl.text;
      }
    });

    _permPincodeCtrl.addListener(() {
      if (_permPincodeCtrl.text.length == 6 && !_isLoadingData) {
        _fetchAreas(_permPincodeCtrl.text, true);
      } else {
        setState(() { _permAreasList.clear(); if (!_isLoadingData) _permArea = ''; });
      }
    });

    _currPincodeCtrl.addListener(() {
      if (_currPincodeCtrl.text.length == 6 && !_sameAsPerm && !_isLoadingData) {
        _fetchAreas(_currPincodeCtrl.text, false);
      } else {
        setState(() { _currAreasList.clear(); if (!_isLoadingData) _currArea = ''; });
      }
    });

    _permLine1Ctrl.addListener(_conditionalSync);
    _permLine2Ctrl.addListener(_conditionalSync);
    _permLandmarkCtrl.addListener(_conditionalSync);
  }

  void _conditionalSync() {
    if (_sameAsPerm) _syncPermToCurr();
  }

  Future<void> _fetchUserData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() { _isLoadingData = false; });
        return;
      }

      final data = await Supabase.instance.client
          .from('contact_details')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _phoneCtrl.text = data['phone'] ?? '+91';
          _whatsappCtrl.text = data['whatsapp_number'] ?? '+91';
          if (_whatsappCtrl.text == _phoneCtrl.text && _phoneCtrl.text != '+91') {
             _sameAsPhone = true;
          }

          _permLine1Ctrl.text = data['permanent_address_line1'] ?? '';
          _permLine2Ctrl.text = data['permanent_address_line2'] ?? '';
          _permPincodeCtrl.text = data['permanent_pincode'] ?? '';
          _permArea = data['permanent_area'] ?? '';
          _permTalukCtrl.text = data['permanent_taluk'] ?? '';
          _permDistrictCtrl.text = data['permanent_district'] ?? '';
          _permDivisionCtrl.text = data['permanent_division'] ?? '';
          _permRegionCtrl.text = data['permanent_region'] ?? '';
          _permStateCtrl.text = data['permanent_state'] ?? '';
          _permCountryCtrl.text = data['permanent_country'] ?? '';
          _permLandmarkCtrl.text = data['permanent_landmark'] ?? '';

          _currLine1Ctrl.text = data['current_address_line1'] ?? '';
          _currLine2Ctrl.text = data['current_address_line2'] ?? '';
          _currPincodeCtrl.text = data['current_pincode'] ?? '';
          _currArea = data['current_area'] ?? '';
          _currTalukCtrl.text = data['current_taluk'] ?? '';
          _currDistrictCtrl.text = data['current_district'] ?? '';
          _currDivisionCtrl.text = data['current_division'] ?? '';
          _currRegionCtrl.text = data['current_region'] ?? '';
          _currStateCtrl.text = data['current_state'] ?? '';
          _currCountryCtrl.text = data['current_country'] ?? '';
          _currLandmarkCtrl.text = data['current_landmark'] ?? '';

          if (_currPincodeCtrl.text.isNotEmpty && _currPincodeCtrl.text == _permPincodeCtrl.text && _currLine1Ctrl.text == _permLine1Ctrl.text) {
             _sameAsPerm = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching contact details: $e');
    } finally {
      if (mounted) setState(() { _isLoadingData = false; });
    }
  }

  Future<void> _saveUserData() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() { _isLoadingData = true; });

    try {
      final contactRow = <String, dynamic>{
        'user_id': userId,
        'phone': _phoneCtrl.text,
        'whatsapp_number': _whatsappCtrl.text,
        'permanent_address_line1': _permLine1Ctrl.text,
        'permanent_address_line2': _permLine2Ctrl.text,
        'permanent_pincode': _permPincodeCtrl.text,
        'permanent_area': _permArea,
        'permanent_taluk': _permTalukCtrl.text,
        'permanent_district': _permDistrictCtrl.text,
        'permanent_division': _permDivisionCtrl.text,
        'permanent_region': _permRegionCtrl.text,
        'permanent_state': _permStateCtrl.text,
        'permanent_country': _permCountryCtrl.text,
        'permanent_landmark': _permLandmarkCtrl.text,
        'current_address_line1': _currLine1Ctrl.text,
        'current_address_line2': _currLine2Ctrl.text,
        'current_pincode': _currPincodeCtrl.text,
        'current_area': _currArea,
        'current_taluk': _currTalukCtrl.text,
        'current_district': _currDistrictCtrl.text,
        'current_division': _currDivisionCtrl.text,
        'current_region': _currRegionCtrl.text,
        'current_state': _currStateCtrl.text,
        'current_country': _currCountryCtrl.text,
        'current_landmark': _currLandmarkCtrl.text,
        'updated_at': DateTime.now().toIso8601String(),
      };
      contactRow['completion_percentage'] = computeContactCompletionPercent(contactRow);
      await Supabase.instance.client.from('contact_details').upsert(contactRow);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact details successfully synced to backend!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error saving contact details: $e');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save to Supabase!')));
      }
    } finally {
      if (mounted) setState(() { _isLoadingData = false; });
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _whatsappCtrl.dispose();
    _permLine1Ctrl.dispose();
    _permLine2Ctrl.dispose();
    _permPincodeCtrl.dispose();
    _permTalukCtrl.dispose();
    _permDistrictCtrl.dispose();
    _permDivisionCtrl.dispose();
    _permRegionCtrl.dispose();
    _permStateCtrl.dispose();
    _permCountryCtrl.dispose();
    _permLandmarkCtrl.dispose();
    _currLine1Ctrl.dispose();
    _currLine2Ctrl.dispose();
    _currPincodeCtrl.dispose();
    _currTalukCtrl.dispose();
    _currDistrictCtrl.dispose();
    _currDivisionCtrl.dispose();
    _currRegionCtrl.dispose();
    _currStateCtrl.dispose();
    _currCountryCtrl.dispose();
    _currLandmarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAreas(String pincode, bool isPermanent) async {
    if (isPermanent) {
      if (!mounted) return;
      setState(() { _isLoadingPerm = true; _permAreasList = []; _permArea = ''; });
    } else {
      if (!mounted) return;
      setState(() { _isLoadingCurr = true; _currAreasList = []; _currArea = ''; });
    }

    try {
      final response = await http.get(Uri.parse('https://api.postalpincode.in/pincode/$pincode'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data.isNotEmpty && data[0]['Status'] == 'Success' && data[0]['PostOffice'] != null) {
          final List postOffices = data[0]['PostOffice'];
          if (mounted) {
            setState(() {
              if (isPermanent) {
                _permAreasList = postOffices;
                if (postOffices.length == 1) _selectArea(postOffices[0], true);
              } else {
                _currAreasList = postOffices;
                if (postOffices.length == 1) _selectArea(postOffices[0], false);
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching pincode: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (isPermanent) _isLoadingPerm = false;
          else _isLoadingCurr = false;
        });
      }
    }
  }

  void _selectArea(dynamic postOffice, bool isPermanent) {
    setState(() {
      if (isPermanent) {
        _permArea = postOffice['Name'] ?? '';
        _permTalukCtrl.text = postOffice['Taluk'] ?? postOffice['Tehsil'] ?? postOffice['Block'] ?? '';
        _permDistrictCtrl.text = postOffice['District'] ?? '';
        _permDivisionCtrl.text = postOffice['Division'] ?? '';
        _permRegionCtrl.text = postOffice['Circle'] ?? postOffice['Region'] ?? '';
        _permStateCtrl.text = postOffice['State'] ?? '';
        _permCountryCtrl.text = postOffice['Country'] ?? '';
        if (_sameAsPerm) _syncPermToCurr();
      } else {
        _currArea = postOffice['Name'] ?? '';
        _currTalukCtrl.text = postOffice['Taluk'] ?? postOffice['Tehsil'] ?? postOffice['Block'] ?? '';
        _currDistrictCtrl.text = postOffice['District'] ?? '';
        _currDivisionCtrl.text = postOffice['Division'] ?? '';
        _currRegionCtrl.text = postOffice['Circle'] ?? postOffice['Region'] ?? '';
        _currStateCtrl.text = postOffice['State'] ?? '';
        _currCountryCtrl.text = postOffice['Country'] ?? '';
      }
    });
  }

  void _syncPermToCurr() {
    if (_sameAsPerm) {
      _currLine1Ctrl.text = _permLine1Ctrl.text;
      _currLine2Ctrl.text = _permLine2Ctrl.text;
      _currPincodeCtrl.text = _permPincodeCtrl.text;
      _currTalukCtrl.text = _permTalukCtrl.text;
      _currDistrictCtrl.text = _permDistrictCtrl.text;
      _currDivisionCtrl.text = _permDivisionCtrl.text;
      _currRegionCtrl.text = _permRegionCtrl.text;
      _currStateCtrl.text = _permStateCtrl.text;
      _currCountryCtrl.text = _permCountryCtrl.text;
      _currLandmarkCtrl.text = _permLandmarkCtrl.text;
      _currArea = _permArea;
      _currAreasList = List.from(_permAreasList);
    } else {
      _currLine1Ctrl.clear();
      _currLine2Ctrl.clear();
      _currPincodeCtrl.clear();
      _currTalukCtrl.clear();
      _currDistrictCtrl.clear();
      _currDivisionCtrl.clear();
      _currRegionCtrl.clear();
      _currStateCtrl.clear();
      _currCountryCtrl.clear();
      _currLandmarkCtrl.clear();
      _currArea = '';
      _currAreasList = [];
    }
  }

  void _showAreaPicker(bool isPermanent) {
    if ((isPermanent && _permAreasList.isEmpty) || (!isPermanent && _currAreasList.isEmpty)) return;
    if (!isPermanent && _sameAsPerm) return;

    final list = isPermanent ? _permAreasList : _currAreasList;

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
                      leading: const Icon(Icons.location_on_outlined, color: Color(0xFF6A11CB)),
                      title: Text(list[i]['Name']),
                      onTap: () {
                        Navigator.pop(ctx);
                        _selectArea(list[i], isPermanent);
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
    bool disabled = !isPermanent && _sameAsPerm;
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

    if (_isLoadingData) {
      return SizedBox(
        height: modalHeight,
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF6A11CB)),
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
                    const Text('Edit Contacts', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF6A11CB))),
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
                _buildTextField('Phone Number', _phoneCtrl, isNumber: true, maxLength: 13),
        Row(
          children: [
            Checkbox(
              value: _sameAsPhone,
              activeColor: const Color(0xFF6A11CB),
              onChanged: (val) {
                setState(() {
                  _sameAsPhone = val ?? false;
                  if (_sameAsPhone) {
                    _whatsappCtrl.text = _phoneCtrl.text;
                  } else {
                    _whatsappCtrl.text = '+91 ';
                  }
                });
              },
            ),
            const Text('WhatsApp same as Phone Number'),
          ],
        ),
        if (!_sameAsPhone)
          _buildTextField('WhatsApp Number', _whatsappCtrl, isNumber: true, maxLength: 13),
        
        const Divider(height: 48),
        const Text('Permanent Address', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        _buildTextField('Address Line 1', _permLine1Ctrl),
        _buildTextField('Address Line 2 (Optional)', _permLine2Ctrl),
        _buildTextField('Pincode (6 Digits)', _permPincodeCtrl, isNumber: true, maxLength: 6),
        _buildAreaDropdown('Select Area / Post Office', _permArea, true, _isLoadingPerm),
        _buildTextField('Taluk / Tehsil', _permTalukCtrl, readOnly: true),
        _buildTextField('District', _permDistrictCtrl, readOnly: true),
        _buildTextField('Division', _permDivisionCtrl, readOnly: true),
        _buildTextField('Region / Circle', _permRegionCtrl, readOnly: true),
        _buildTextField('State', _permStateCtrl, readOnly: true),
        _buildTextField('Country', _permCountryCtrl, readOnly: true),
        _buildTextField('Landmark (Optional)', _permLandmarkCtrl),

        const Divider(height: 48),
        const Text('Current Address', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(
          children: [
            Checkbox(
              value: _sameAsPerm,
              activeColor: const Color(0xFF6A11CB),
              onChanged: (val) {
                setState(() {
                  _sameAsPerm = val ?? false;
                  _syncPermToCurr();
                });
              },
            ),
            const Text('Same as Permanent Address'),
          ],
        ),
        const SizedBox(height: 16),
        if (!_sameAsPerm) ...[
          _buildTextField('Address Line 1', _currLine1Ctrl),
          _buildTextField('Address Line 2 (Optional)', _currLine2Ctrl),
          _buildTextField('Pincode (6 Digits)', _currPincodeCtrl, isNumber: true, maxLength: 6),
          _buildAreaDropdown('Select Area / Post Office', _currArea, false, _isLoadingCurr),
          _buildTextField('Taluk / Tehsil', _currTalukCtrl, readOnly: true),
          _buildTextField('District', _currDistrictCtrl, readOnly: true),
          _buildTextField('Division', _currDivisionCtrl, readOnly: true),
          _buildTextField('Region / Circle', _currRegionCtrl, readOnly: true),
          _buildTextField('State', _currStateCtrl, readOnly: true),
          _buildTextField('Country', _currCountryCtrl, readOnly: true),
          _buildTextField('Landmark (Optional)', _currLandmarkCtrl),
        ],

        const SizedBox(height: 32),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: _saveUserData,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6A11CB),
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
