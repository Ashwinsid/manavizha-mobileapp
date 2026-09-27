import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_profile_completion.dart';

/// Shared contact-details fetch/save/pincode-lookup logic. Extracted so
/// `ContactDetailsEditorSheet` (all fields on one page) and
/// `ContactDetailsQASheet` (one question at a time) hit the same pincode
/// API, the same "same as phone/permanent" sync rules, and the same
/// `contact_details` upsert — no drift between the two UIs.
///
/// Note: `saveUserData()` has no required-field validation, matching the
/// mobile app's real (permissive) save behavior today — unlike the web
/// app's Contact Details step, which requires phone/whatsapp/addresses.
mixin ContactDetailsLogic<T extends StatefulWidget> on State<T> {
  bool isLoadingData = true;

  final phoneCtrl = TextEditingController(text: '+91');
  final whatsappCtrl = TextEditingController(text: '+91');
  bool sameAsPhone = false;

  final permLine1Ctrl = TextEditingController();
  final permLine2Ctrl = TextEditingController();
  final permPincodeCtrl = TextEditingController();
  final permTalukCtrl = TextEditingController();
  final permDistrictCtrl = TextEditingController();
  final permDivisionCtrl = TextEditingController();
  final permRegionCtrl = TextEditingController();
  final permStateCtrl = TextEditingController();
  final permCountryCtrl = TextEditingController();
  final permLandmarkCtrl = TextEditingController();
  String permArea = '';
  List<dynamic> permAreasList = [];
  bool isLoadingPerm = false;

  bool sameAsPerm = false;

  final currLine1Ctrl = TextEditingController();
  final currLine2Ctrl = TextEditingController();
  final currPincodeCtrl = TextEditingController();
  final currTalukCtrl = TextEditingController();
  final currDistrictCtrl = TextEditingController();
  final currDivisionCtrl = TextEditingController();
  final currRegionCtrl = TextEditingController();
  final currStateCtrl = TextEditingController();
  final currCountryCtrl = TextEditingController();
  final currLandmarkCtrl = TextEditingController();
  String currArea = '';
  List<dynamic> currAreasList = [];
  bool isLoadingCurr = false;

  void initContactDetailsLogic() {
    fetchUserData();

    phoneCtrl.addListener(() {
      if (sameAsPhone) {
        whatsappCtrl.text = phoneCtrl.text;
      }
    });

    permPincodeCtrl.addListener(() {
      if (permPincodeCtrl.text.length == 6 && !isLoadingData) {
        fetchAreas(permPincodeCtrl.text, true);
      } else {
        setState(() {
          permAreasList.clear();
          if (!isLoadingData) permArea = '';
        });
      }
    });

    currPincodeCtrl.addListener(() {
      if (currPincodeCtrl.text.length == 6 && !sameAsPerm && !isLoadingData) {
        fetchAreas(currPincodeCtrl.text, false);
      } else {
        setState(() {
          currAreasList.clear();
          if (!isLoadingData) currArea = '';
        });
      }
    });

    permLine1Ctrl.addListener(_conditionalSync);
    permLine2Ctrl.addListener(_conditionalSync);
    permLandmarkCtrl.addListener(_conditionalSync);
  }

  void _conditionalSync() {
    if (sameAsPerm) syncPermToCurr();
  }

  Future<void> fetchUserData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() { isLoadingData = false; });
        return;
      }

      final data = await Supabase.instance.client
          .from('contact_details')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          phoneCtrl.text = data['phone'] ?? '+91';
          whatsappCtrl.text = data['whatsapp_number'] ?? '+91';
          if (whatsappCtrl.text == phoneCtrl.text && phoneCtrl.text != '+91') {
            sameAsPhone = true;
          }

          permLine1Ctrl.text = data['permanent_address_line1'] ?? '';
          permLine2Ctrl.text = data['permanent_address_line2'] ?? '';
          permPincodeCtrl.text = data['permanent_pincode'] ?? '';
          permArea = data['permanent_area'] ?? '';
          permTalukCtrl.text = data['permanent_taluk'] ?? '';
          permDistrictCtrl.text = data['permanent_district'] ?? '';
          permDivisionCtrl.text = data['permanent_division'] ?? '';
          permRegionCtrl.text = data['permanent_region'] ?? '';
          permStateCtrl.text = data['permanent_state'] ?? '';
          permCountryCtrl.text = data['permanent_country'] ?? '';
          permLandmarkCtrl.text = data['permanent_landmark'] ?? '';

          currLine1Ctrl.text = data['current_address_line1'] ?? '';
          currLine2Ctrl.text = data['current_address_line2'] ?? '';
          currPincodeCtrl.text = data['current_pincode'] ?? '';
          currArea = data['current_area'] ?? '';
          currTalukCtrl.text = data['current_taluk'] ?? '';
          currDistrictCtrl.text = data['current_district'] ?? '';
          currDivisionCtrl.text = data['current_division'] ?? '';
          currRegionCtrl.text = data['current_region'] ?? '';
          currStateCtrl.text = data['current_state'] ?? '';
          currCountryCtrl.text = data['current_country'] ?? '';
          currLandmarkCtrl.text = data['current_landmark'] ?? '';

          if (currPincodeCtrl.text.isNotEmpty &&
              currPincodeCtrl.text == permPincodeCtrl.text &&
              currLine1Ctrl.text == permLine1Ctrl.text) {
            sameAsPerm = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching contact details: $e');
    } finally {
      if (mounted) setState(() { isLoadingData = false; });
    }
  }

  Future<void> saveUserData({VoidCallback? onSaved}) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() { isLoadingData = true; });

    try {
      final contactRow = <String, dynamic>{
        'user_id': userId,
        'phone': phoneCtrl.text,
        'whatsapp_number': whatsappCtrl.text,
        'permanent_address_line1': permLine1Ctrl.text,
        'permanent_address_line2': permLine2Ctrl.text,
        'permanent_pincode': permPincodeCtrl.text,
        'permanent_area': permArea,
        'permanent_taluk': permTalukCtrl.text,
        'permanent_district': permDistrictCtrl.text,
        'permanent_division': permDivisionCtrl.text,
        'permanent_region': permRegionCtrl.text,
        'permanent_state': permStateCtrl.text,
        'permanent_country': permCountryCtrl.text,
        'permanent_landmark': permLandmarkCtrl.text,
        'current_address_line1': currLine1Ctrl.text,
        'current_address_line2': currLine2Ctrl.text,
        'current_pincode': currPincodeCtrl.text,
        'current_area': currArea,
        'current_taluk': currTalukCtrl.text,
        'current_district': currDistrictCtrl.text,
        'current_division': currDivisionCtrl.text,
        'current_region': currRegionCtrl.text,
        'current_state': currStateCtrl.text,
        'current_country': currCountryCtrl.text,
        'current_landmark': currLandmarkCtrl.text,
        'updated_at': DateTime.now().toIso8601String(),
      };
      contactRow['completion_percentage'] = computeContactCompletionPercent(contactRow);
      await Supabase.instance.client.from('contact_details').upsert(contactRow);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact details successfully synced to backend!')));
        onSaved?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error saving contact details: $e');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save to Supabase!')));
      }
    } finally {
      if (mounted) setState(() { isLoadingData = false; });
    }
  }

  Future<void> fetchAreas(String pincode, bool isPermanent) async {
    if (isPermanent) {
      if (!mounted) return;
      setState(() { isLoadingPerm = true; permAreasList = []; permArea = ''; });
    } else {
      if (!mounted) return;
      setState(() { isLoadingCurr = true; currAreasList = []; currArea = ''; });
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
                permAreasList = postOffices;
                if (postOffices.length == 1) selectArea(postOffices[0], true);
              } else {
                currAreasList = postOffices;
                if (postOffices.length == 1) selectArea(postOffices[0], false);
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
          if (isPermanent) isLoadingPerm = false;
          else isLoadingCurr = false;
        });
      }
    }
  }

  void selectArea(dynamic postOffice, bool isPermanent) {
    setState(() {
      if (isPermanent) {
        permArea = postOffice['Name'] ?? '';
        permTalukCtrl.text = postOffice['Taluk'] ?? postOffice['Tehsil'] ?? postOffice['Block'] ?? '';
        permDistrictCtrl.text = postOffice['District'] ?? '';
        permDivisionCtrl.text = postOffice['Division'] ?? '';
        permRegionCtrl.text = postOffice['Circle'] ?? postOffice['Region'] ?? '';
        permStateCtrl.text = postOffice['State'] ?? '';
        permCountryCtrl.text = postOffice['Country'] ?? '';
        if (sameAsPerm) syncPermToCurr();
      } else {
        currArea = postOffice['Name'] ?? '';
        currTalukCtrl.text = postOffice['Taluk'] ?? postOffice['Tehsil'] ?? postOffice['Block'] ?? '';
        currDistrictCtrl.text = postOffice['District'] ?? '';
        currDivisionCtrl.text = postOffice['Division'] ?? '';
        currRegionCtrl.text = postOffice['Circle'] ?? postOffice['Region'] ?? '';
        currStateCtrl.text = postOffice['State'] ?? '';
        currCountryCtrl.text = postOffice['Country'] ?? '';
      }
    });
  }

  void syncPermToCurr() {
    if (sameAsPerm) {
      currLine1Ctrl.text = permLine1Ctrl.text;
      currLine2Ctrl.text = permLine2Ctrl.text;
      currPincodeCtrl.text = permPincodeCtrl.text;
      currTalukCtrl.text = permTalukCtrl.text;
      currDistrictCtrl.text = permDistrictCtrl.text;
      currDivisionCtrl.text = permDivisionCtrl.text;
      currRegionCtrl.text = permRegionCtrl.text;
      currStateCtrl.text = permStateCtrl.text;
      currCountryCtrl.text = permCountryCtrl.text;
      currLandmarkCtrl.text = permLandmarkCtrl.text;
      currArea = permArea;
      currAreasList = List.from(permAreasList);
    } else {
      currLine1Ctrl.clear();
      currLine2Ctrl.clear();
      currPincodeCtrl.clear();
      currTalukCtrl.clear();
      currDistrictCtrl.clear();
      currDivisionCtrl.clear();
      currRegionCtrl.clear();
      currStateCtrl.clear();
      currCountryCtrl.clear();
      currLandmarkCtrl.clear();
      currArea = '';
      currAreasList = [];
    }
  }

  void disposeContactDetailsLogic() {
    phoneCtrl.dispose();
    whatsappCtrl.dispose();
    permLine1Ctrl.dispose();
    permLine2Ctrl.dispose();
    permPincodeCtrl.dispose();
    permTalukCtrl.dispose();
    permDistrictCtrl.dispose();
    permDivisionCtrl.dispose();
    permRegionCtrl.dispose();
    permStateCtrl.dispose();
    permCountryCtrl.dispose();
    permLandmarkCtrl.dispose();
    currLine1Ctrl.dispose();
    currLine2Ctrl.dispose();
    currPincodeCtrl.dispose();
    currTalukCtrl.dispose();
    currDistrictCtrl.dispose();
    currDivisionCtrl.dispose();
    currRegionCtrl.dispose();
    currStateCtrl.dispose();
    currCountryCtrl.dispose();
    currLandmarkCtrl.dispose();
  }
}
