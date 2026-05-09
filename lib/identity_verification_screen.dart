import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_home_screen.dart';
import 'user_profile_completion.dart';

/// In-app identity verification flow (mirrors [manavizha/components/verification-dialog.tsx]).
///
/// 3 steps:
///   1. Pick one of the user's existing profile photos as the "comparison" reference.
///   2. Capture a live front-camera selfie.
///   3. Review the pair side-by-side and submit.
///
/// On submit the selfie is uploaded to the `user-photos` Supabase bucket as
/// `{userId}/verification_live_selfie_{timestamp}.jpg`, then the `photos` row is upserted with
/// `verification_status = pending`, `live_photo_url`, `comparison_photo_url`.
class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  State<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends State<IdentityVerificationScreen> {
  static const Color _brand = AdminHomeScreen.brandPurple;
  static const Color _pageBg = Color(0xFFF8F9FE);

  final ImagePicker _imagePicker = ImagePicker();

  bool _loading = true;
  String? _loadError;

  /// Already-signed `user-photos` URLs the user can pick from.
  List<String> _existingPhotos = [];
  String? _selectedPhotoUrl;

  XFile? _selfie;

  int _step = 1;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadExistingPhotos();
  }

  Future<void> _loadExistingPhotos() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) {
        throw Exception('Not signed in');
      }

      final res = await client
          .from('photos')
          .select('user_photos')
          .eq('user_id', uid)
          .maybeSingle();

      final raw = parseUserPhotosList(res?['user_photos']);
      final signed = <String>[];
      for (final entry in raw) {
        final url = entry?.toString() ?? '';
        if (url.isEmpty) continue;
        final s = await signUserProfilePhoto(client, uid, url);
        if (s != null && s.isNotEmpty) signed.add(s);
      }

      if (!mounted) return;
      setState(() {
        _existingPhotos = signed;
        _selectedPhotoUrl = signed.isNotEmpty ? signed.first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load your photos. $e';
        _loading = false;
      });
    }
  }

  Future<void> _captureSelfie() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 1280,
        maxHeight: 1280,
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _selfie = picked;
        _step = 3;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: $e')),
      );
    }
  }

  Future<void> _submit() async {
    final selfie = _selfie;
    final compare = _selectedPhotoUrl;
    if (selfie == null || compare == null) return;

    setState(() => _submitting = true);

    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _submitting = false);
      return;
    }

    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '$uid/verification_live_selfie_$ts.jpg';
      final bytes = await selfie.readAsBytes();

      await client.storage.from('user-photos').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );

      final signedUrl =
          await client.storage.from('user-photos').createSignedUrl(path, 31536000);

      await client.from('photos').upsert({
        'user_id': uid,
        'verification_status': 'pending',
        'live_photo_url': signedUrl,
        'comparison_photo_url': compare,
        'created_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification submitted! An admin will review it soon.'),
          backgroundColor: Color(0xFF15803D),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit verification: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        title: const Text(
          'Verify identity',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: (_step / 3).clamp(0.0, 1.0),
            minHeight: 3,
            backgroundColor: const Color(0xFFE5E7EB),
            valueColor: const AlwaysStoppedAnimation<Color>(_brand),
          ),
        ),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _brand));
    }
    if (_loadError != null) {
      return _ErrorRetry(message: _loadError!, onRetry: _loadExistingPhotos);
    }
    switch (_step) {
      case 1:
        return _buildStep1();
      case 2:
        return _buildStep2();
      default:
        return _buildStep3();
    }
  }

  // -------------------- Step 1: pick comparison photo --------------------

  Widget _buildStep1() {
    final hasPhotos = _existingPhotos.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            children: [
              const _StepHeader(
                step: 'Step 1 of 3',
                title: 'Pick a profile photo',
                subtitle:
                    'This is the photo we’ll compare with your live selfie. Choose a clear front-facing image.',
              ),
              const SizedBox(height: 20),
              if (hasPhotos)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _existingPhotos.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1,
                  ),
                  itemBuilder: (context, index) {
                    final url = _existingPhotos[index];
                    final selected = url == _selectedPhotoUrl;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedPhotoUrl = url),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: selected ? _brand : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: _brand.withValues(alpha: 0.25),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  color: const Color(0xFFEDEEF3),
                                  child: const Icon(Icons.broken_image_outlined,
                                      color: Colors.black26),
                                ),
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: _brand),
                                    ),
                                  );
                                },
                              ),
                              if (selected)
                                Container(
                                  alignment: Alignment.center,
                                  color: _brand.withValues(alpha: 0.12),
                                  child: const Icon(
                                    Icons.check_circle_rounded,
                                    color: _brand,
                                    size: 32,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                )
              else
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.image_outlined,
                          color: Colors.indigo.shade300, size: 40),
                      const SizedBox(height: 12),
                      const Text(
                        'No profile photos uploaded yet.',
                        style:
                            TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Upload at least one profile photo first, then come back here to verify.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _StickyFooter(
          child: ElevatedButton(
            onPressed: _selectedPhotoUrl == null ? null : () => setState(() => _step = 2),
            style: ElevatedButton.styleFrom(
              backgroundColor: _brand,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Next: Take a selfie',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // -------------------- Step 2: capture selfie --------------------

  Widget _buildStep2() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            children: [
              const _StepHeader(
                step: 'Step 2 of 3',
                title: 'Take a live selfie',
                subtitle:
                    'We’ll use this to confirm your profile is genuine. Make sure your face is well-lit and clearly visible.',
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: _brand.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_front_rounded,
                        color: _brand,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Open the front camera',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tap below to launch the camera and capture a clear front-facing selfie.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _captureSelfie,
                      icon: const Icon(Icons.photo_camera_rounded),
                      label: const Text('Open camera'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _brand,
                        side: const BorderSide(color: _brand),
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const _GuidelinesCard(
                items: [
                  'Look directly at the camera.',
                  'Remove sunglasses, hats and masks.',
                  'Use natural light if possible.',
                  'Don’t use filters or edited photos.',
                ],
              ),
            ],
          ),
        ),
        _StickyFooter(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _step = 1),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    foregroundColor: Colors.black54,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Back',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _captureSelfie,
                  icon: const Icon(Icons.photo_camera_rounded, color: Colors.white),
                  label: const Text(
                    'Capture selfie',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -------------------- Step 3: review + submit --------------------

  Widget _buildStep3() {
    final selfiePath = _selfie?.path;
    final compareUrl = _selectedPhotoUrl;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            children: [
              const _StepHeader(
                step: 'Step 3 of 3',
                title: 'Review and submit',
                subtitle:
                    'Make sure both photos are clear. An admin will compare them to verify your identity.',
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PhotoPreview(
                      label: 'Profile photo',
                      labelColor: Colors.indigo.shade700,
                      child: compareUrl == null
                          ? const _NoPreview()
                          : Image.network(compareUrl, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PhotoPreview(
                      label: 'Live selfie',
                      labelColor: Colors.amber.shade800,
                      child: selfiePath == null
                          ? const _NoPreview()
                          : Image.file(File(selfiePath), fit: BoxFit.cover),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'By submitting, you agree to let our admins compare these photos for identity verification.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade900,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _StickyFooter(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _submitting ? null : () => setState(() => _step = 2),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    foregroundColor: Colors.black54,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Retake',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brand,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Submit for verification',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------- Reusable section pieces (kept private to this screen) ----------

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  final String step;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          step.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            color: Colors.black54,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black54,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _StickyFooter extends StatelessWidget {
  const _StickyFooter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GuidelinesCard extends StatelessWidget {
  const _GuidelinesCard({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tips for a clean selfie',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 8),
          for (final t in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_outline_rounded,
                        color: Color(0xFF15803D), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black87, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.label,
    required this.labelColor,
    required this.child,
  });

  final String label;
  final Color labelColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              color: const Color(0xFFEDEEF3),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoPreview extends StatelessWidget {
  const _NoPreview();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.image_outlined, color: Colors.black26, size: 36),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
