import 'package:flutter/material.dart';

import 'contact_details_logic.dart';

/// One-question-at-a-time version of `ContactDetailsEditorSheet`. Same
/// fields, same pincode auto-lookup and "same as phone/permanent" sync
/// rules (via [ContactDetailsLogic]) as the all-fields editor.
///
/// `saveUserData()` has no required-field validation in this app (unlike
/// the web app's Contact Details step), so every question here is
/// skippable — Next is never disabled.
class ContactDetailsQASheet extends StatefulWidget {
  const ContactDetailsQASheet({super.key});

  @override
  State<ContactDetailsQASheet> createState() => _ContactDetailsQASheetState();
}

class _QAField {
  final String id;
  final String title;
  final String? subtitle;
  final Widget Function(StateSetter setModalState) builder;
  _QAField({required this.id, required this.title, this.subtitle, required this.builder});
}

class _ContactDetailsQASheetState extends State<ContactDetailsQASheet> with ContactDetailsLogic {
  int _qIndex = 0;

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

  Widget _textField(TextEditingController controller, {String? hint, bool isNumber = false, int? maxLength, StateSetter? setModalState}) {
    return TextField(
      controller: controller,
      autofocus: true,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLength: maxLength,
      onChanged: (_) => (setModalState ?? setState)(() {}),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showAreaPicker(bool isPermanent, StateSetter setModalState) {
    final list = isPermanent ? permAreasList : currAreasList;
    if (list.isEmpty) return;

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
                  itemBuilder: (ctx, i) => ListTile(
                    leading: const Icon(Icons.location_on_outlined, color: Color(0xFF2FA086)),
                    title: Text(list[i]['Name']),
                    onTap: () {
                      Navigator.pop(ctx);
                      selectArea(list[i], isPermanent);
                      setModalState(() {});
                      setState(() {});
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _areaPicker(bool isPermanent, bool isLoading, StateSetter setModalState) {
    final value = isPermanent ? permArea : currArea;
    return GestureDetector(
      onTap: () => _showAreaPicker(isPermanent, setModalState),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              value.isEmpty ? (isLoading ? 'Scanning...' : 'Select Area') : value,
              style: TextStyle(fontSize: 16, color: value.isEmpty ? Colors.black54 : Colors.black87),
            ),
            if (isLoading)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.arrow_drop_down, color: Colors.black54),
          ],
        ),
      ),
    );
  }

  String? _areaSubtitle(bool isPermanent) {
    final taluk = (isPermanent ? permTalukCtrl : currTalukCtrl).text;
    final district = (isPermanent ? permDistrictCtrl : currDistrictCtrl).text;
    if (taluk.isEmpty && district.isEmpty) return null;
    if (taluk.isEmpty) return district;
    if (district.isEmpty) return taluk;
    return '$taluk, $district';
  }

  List<_QAField> _buildFields() {
    final fields = <_QAField>[
      _QAField(
        id: 'phone',
        title: "What's your phone number?",
        builder: (setModalState) => _textField(phoneCtrl, hint: 'e.g., +91 9876543210', isNumber: true, maxLength: 13, setModalState: setModalState),
      ),
      _QAField(
        id: 'whatsapp',
        title: "What's your WhatsApp number?",
        builder: (setModalState) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: sameAsPhone,
                  activeColor: const Color(0xFF2FA086),
                  onChanged: (val) => setModalState(() {
                    sameAsPhone = val ?? false;
                    whatsappCtrl.text = sameAsPhone ? phoneCtrl.text : '+91 ';
                  }),
                ),
                const Text('Same as Phone Number'),
              ],
            ),
            if (!sameAsPhone) _textField(whatsappCtrl, hint: 'e.g., +91 9876543210', isNumber: true, maxLength: 13, setModalState: setModalState),
          ],
        ),
      ),
      _QAField(
        id: 'permAddress',
        title: 'What is your permanent address?',
        subtitle: 'Line 2 is optional.',
        builder: (setModalState) => Column(
          children: [
            _textField(permLine1Ctrl, hint: 'Address Line 1', setModalState: setModalState),
            const SizedBox(height: 12),
            _textField(permLine2Ctrl, hint: 'Address Line 2 (optional)', setModalState: setModalState),
          ],
        ),
      ),
      _QAField(
        id: 'permPincode',
        title: "What's the pincode there?",
        subtitle: "We'll look up the area, taluk and district automatically.",
        builder: (setModalState) => _textField(permPincodeCtrl, hint: 'e.g., 625001', isNumber: true, maxLength: 6, setModalState: setModalState),
      ),
      _QAField(
        id: 'permArea',
        title: 'Which area?',
        subtitle: _areaSubtitle(true),
        builder: (setModalState) => _areaPicker(true, isLoadingPerm, setModalState),
      ),
      _QAField(
        id: 'permLandmark',
        title: 'Any nearby landmark?',
        subtitle: 'Optional.',
        builder: (setModalState) => _textField(permLandmarkCtrl, hint: 'e.g., Near Meenakshi Temple', setModalState: setModalState),
      ),
      _QAField(
        id: 'sameAsPerm',
        title: 'Is your current address the same as your permanent address?',
        builder: (setModalState) => Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setModalState(() {
                  sameAsPerm = true;
                  syncPermToCurr();
                }),
                style: OutlinedButton.styleFrom(
                  backgroundColor: sameAsPerm ? const Color(0xFF2FA086) : null,
                  foregroundColor: sameAsPerm ? Colors.white : const Color(0xFF2FA086),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Yes, same'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => setModalState(() {
                  sameAsPerm = false;
                  syncPermToCurr();
                }),
                style: OutlinedButton.styleFrom(
                  backgroundColor: !sameAsPerm ? const Color(0xFF2FA086) : null,
                  foregroundColor: !sameAsPerm ? Colors.white : const Color(0xFF2FA086),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('No, different'),
              ),
            ),
          ],
        ),
      ),
    ];

    if (!sameAsPerm) {
      fields.addAll([
        _QAField(
          id: 'currAddress',
          title: "What's your current address?",
          subtitle: 'Line 2 is optional.',
          builder: (setModalState) => Column(
            children: [
              _textField(currLine1Ctrl, hint: 'Address Line 1', setModalState: setModalState),
              const SizedBox(height: 12),
              _textField(currLine2Ctrl, hint: 'Address Line 2 (optional)', setModalState: setModalState),
            ],
          ),
        ),
        _QAField(
          id: 'currPincode',
          title: "What's the current address pincode?",
          builder: (setModalState) => _textField(currPincodeCtrl, hint: 'e.g., 625001', isNumber: true, maxLength: 6, setModalState: setModalState),
        ),
        _QAField(
          id: 'currArea',
          title: 'Which area?',
          subtitle: _areaSubtitle(false),
          builder: (setModalState) => _areaPicker(false, isLoadingCurr, setModalState),
        ),
        _QAField(
          id: 'currLandmark',
          title: 'Any nearby landmark?',
          subtitle: 'Optional.',
          builder: (setModalState) => _textField(currLandmarkCtrl, hint: 'e.g., Near City Hospital', setModalState: setModalState),
        ),
      ]);
    }

    return fields;
  }

  @override
  Widget build(BuildContext context) {
    final double modalHeight = MediaQuery.of(context).size.height * 0.85;

    if (isLoadingData) {
      return SizedBox(height: modalHeight, child: const Center(child: CircularProgressIndicator(color: Color(0xFF2FA086))));
    }

    return StatefulBuilder(
      builder: (context, setModalState) {
        final fields = _buildFields();
        final safeIndex = _qIndex >= fields.length ? fields.length - 1 : _qIndex;
        final current = fields[safeIndex];
        final isLast = safeIndex == fields.length - 1;

        return Container(
          height: modalHeight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Question ${safeIndex + 1} of ${fields.length}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF2FA086))),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (safeIndex + 1) / fields.length,
                  minHeight: 6,
                  backgroundColor: Colors.black12,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF2FA086)),
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      key: ValueKey(current.id),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(current.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        if (current.subtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(current.subtitle!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                        ],
                        const SizedBox(height: 20),
                        current.builder(setModalState),
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
                        onPressed: () => setModalState(() => _qIndex = safeIndex - 1),
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
                      onPressed: isLast
                          ? () => saveUserData()
                          : () => setModalState(() => _qIndex = safeIndex + 1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2FA086),
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
      },
    );
  }
}
