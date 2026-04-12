import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One entry in a [RadialMenu].
class RadialMenuItem {
  const RadialMenuItem({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.pageName,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  /// Shown to the **left** of the icon only on the two innermost rim slots (highest opacity).
  final String? pageName;
}

/// Full-donut background (outer disk − inner disk) for the dial panel.
class RadialMenuRingBackgroundPainter extends CustomPainter {
  RadialMenuRingBackgroundPainter({
    required this.center,
    required this.outerRadius,
    required this.innerRadius,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
  });

  final Offset center;
  final double outerRadius;
  final double innerRadius;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Rect.fromCircle(center: center, radius: outerRadius);
    final inner = Rect.fromCircle(center: center, radius: innerRadius);
    final outerDisk = Path()..addOval(outer);

    if (innerRadius <= 0 || innerRadius >= outerRadius) {
      final fill = Paint()
        ..color = fillColor
        ..isAntiAlias = true;
      canvas.drawShadow(outerDisk, Colors.black26, 6, false);
      canvas.drawPath(outerDisk, fill);
      final stroke = Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..isAntiAlias = true;
      canvas.drawOval(outer, stroke);
      return;
    }

    final innerDisk = Path()..addOval(inner);
    final ring = Path.combine(PathOperation.difference, outerDisk, innerDisk);
    final fill = Paint()
      ..color = fillColor
      ..isAntiAlias = true;
    canvas.drawShadow(ring, Colors.black26, 6, false);
    canvas.drawPath(ring, fill);
    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    canvas.drawOval(outer, stroke);
    canvas.drawOval(inner, stroke);
  }

  @override
  bool shouldRepaint(covariant RadialMenuRingBackgroundPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.outerRadius != outerRadius ||
        oldDelegate.innerRadius != innerRadius ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Rotary-style radial menu: conceptual 360° list; only a 180° window is clipped and shown.
///
/// Uses [visibleSlots] fixed positions on the semicircle (default 6 → 30° steps:
/// -75°, -45°, …, +75°). Drag updates rotation; release snaps with [Curves.easeOut].
class RadialMenu extends StatefulWidget {
  const RadialMenu({
    super.key,
    required this.items,
    required this.radius,
    required this.center,
    required this.size,
    this.visibleSlots = 6,
    this.itemDiameter = 52,
    this.rotationSensitivity = 0.45,
    this.snapDuration = const Duration(milliseconds: 320),
    this.backgroundPainter,
    this.iconColor = const Color(0xFF3D1466),
    this.itemBackgroundColor = const Color(0xFFF3E5FF),
    this.brandColor = const Color(0xFF6A11CB),
    this.showHapticOnSnap = true,
    this.clipOuterRadius,
    this.clipInnerRadius,
  });

  final List<RadialMenuItem> items;
  final double radius;
  final Offset center;
  final Size size;
  final int visibleSlots;
  final double itemDiameter;
  final double rotationSensitivity;
  final Duration snapDuration;
  final CustomPainter? backgroundPainter;
  final Color iconColor;
  final Color itemBackgroundColor;
  final Color brandColor;
  final bool showHapticOnSnap;

  /// Ring bounds for [ClipPath] — must match [RadialMenuRingBackgroundPainter] radii.
  /// If null, defaults use [radius] + [itemDiameter] (same formulas as the home FAB dial).
  final double? clipOuterRadius;
  final double? clipInnerRadius;

  /// Visible arc in user degrees: [-90, 90] (180° total), 0° = toward negative X.
  static const double visibleHalfDeg = 90;

  @override
  State<RadialMenu> createState() => _RadialMenuState();
}

class _RadialMenuState extends State<RadialMenu> with SingleTickerProviderStateMixin {
  late AnimationController _snapController;
  Animation<double>? _snapAnimation;

  /// Virtual rotation in **degrees**; snapping uses [stepDeg] increments.
  double _rotationDeg = 0;

  double get _stepDeg => 180.0 / widget.visibleSlots;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(vsync: this, duration: widget.snapDuration);
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  double _snapTarget(double value) {
    final s = _stepDeg;
    return (value / s).round() * s;
  }

  void _animateRotationTo(double target) {
    _snapAnimation?.removeListener(_snapTick);
    _snapAnimation?.removeStatusListener(_snapDone);

    final begin = _rotationDeg;
    final curved = CurvedAnimation(parent: _snapController, curve: Curves.easeOut);
    _snapAnimation = Tween<double>(begin: begin, end: target).animate(curved);
    _snapAnimation!.addListener(_snapTick);
    _snapAnimation!.addStatusListener(_snapDone);
    _snapController.forward(from: 0);
  }

  void _snapTick() {
    if (_snapAnimation != null) {
      setState(() => _rotationDeg = _snapAnimation!.value);
    }
  }

  void _snapDone(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _snapAnimation?.removeListener(_snapTick);
      _snapAnimation?.removeStatusListener(_snapDone);
      if (widget.showHapticOnSnap) {
        HapticFeedback.selectionClick();
      }
    }
  }

  void _onPanEnd() {
    final target = _snapTarget(_rotationDeg);
    if ((target - _rotationDeg).abs() < 1e-6) {
      return;
    }
    _animateRotationTo(target);
  }

  /// Slot angles: -90 + step*(j+0.5) → e.g. -75,-45,…,+75 for 6 slots.
  List<double> _slotAnglesDeg() {
    final step = _stepDeg;
    return List<double>.generate(
      widget.visibleSlots,
      (j) => -RadialMenu.visibleHalfDeg + step * (j + 0.5),
    );
  }

  int _positiveMod(int a, int m) {
    if (m <= 0) return 0;
    return ((a % m) + m) % m;
  }

  int _itemIndexAtSlot(int slotIndex) {
    final m = widget.items.length;
    if (m == 0) return 0;
    final shift = -(_rotationDeg / _stepDeg).round();
    return _positiveMod(shift + slotIndex, m);
  }

  /// User angle 0° = left; θ_math = π + rad.
  Offset _offsetForUserAngleDeg(double userDeg) {
    final rad = userDeg * math.pi / 180.0;
    final theta = math.pi + rad;
    return Offset(
      widget.center.dx + widget.radius * math.cos(theta),
      widget.center.dy + widget.radius * math.sin(theta),
    );
  }

  double _scaleForSlotAngleAbs(double slotDegAbs) {
    final t = (slotDegAbs / RadialMenu.visibleHalfDeg).clamp(0.0, 1.0);
    return 1.2 - t * 0.3;
  }

  double _opacityForSlotAngleAbs(double slotDegAbs) {
    final t = (slotDegAbs / RadialMenu.visibleHalfDeg).clamp(0.0, 1.0);
    return 1.0 - t * 0.5;
  }

  /// The two innermost rim positions (smallest [|angle|]) match full-opacity tier — labels only there.
  bool _showsPageLabel(double slotDegAbs) {
    return slotDegAbs <= _stepDeg * 0.5 + 1e-6;
  }

  static const double _pageLabelGap = 16;
  static const double _pageLabelMaxWidth = 120;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return SizedBox(width: widget.size.width, height: widget.size.height);
    }

    final slots = _slotAnglesDeg();
    var centerSlotJ = 0;
    for (var j = 1; j < slots.length; j++) {
      if (slots[j].abs() < slots[centerSlotJ].abs()) centerSlotJ = j;
    }

    final clipOuter = widget.clipOuterRadius ??
        widget.radius + widget.itemDiameter / 2 + 14;
    final clipInner = widget.clipInnerRadius ??
        (widget.radius - widget.itemDiameter / 2 - 10).clamp(12.0, double.infinity).toDouble();

    return SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipPath(
            clipper: _DialRingClipper(
              center: widget.center,
              outerRadius: clipOuter,
              innerRadius: clipInner,
              panelRight: widget.size.width,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanUpdate: (details) {
                _snapController.stop();
                _snapAnimation?.removeListener(_snapTick);
                _snapAnimation?.removeStatusListener(_snapDone);
                setState(() {
                  _rotationDeg += details.delta.dy * widget.rotationSensitivity * 0.65 +
                      details.delta.dx * widget.rotationSensitivity * 0.4;
                });
              },
              onPanEnd: (_) => _onPanEnd(),
              onPanCancel: _onPanEnd,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (widget.backgroundPainter != null)
                    CustomPaint(
                      size: widget.size,
                      painter: widget.backgroundPainter,
                    ),
                  for (var j = 0; j < widget.visibleSlots; j++)
                    _buildSlotIcon(j, slots[j], j == centerSlotJ),
                ],
              ),
            ),
          ),
          // Page titles sit outside the ring clip; otherwise [ClipPath] removes them entirely.
          for (var j = 0; j < widget.visibleSlots; j++)
            _buildSlotPageLabel(context, j, slots[j]),
        ],
      ),
    );
  }

  Widget _buildSlotIcon(int j, double slotDeg, bool isCenterSlot) {
    final item = widget.items[_itemIndexAtSlot(j)];
    final abs = slotDeg.abs();
    final o = _offsetForUserAngleDeg(slotDeg);
    final d = widget.itemDiameter;

    return Positioned(
      left: (o.dx - d / 2).clamp(0.0, widget.size.width - d),
      top: (o.dy - d / 2).clamp(0.0, widget.size.height - d),
      child: Opacity(
        opacity: _opacityForSlotAngleAbs(abs),
        child: Transform.scale(
          scale: _scaleForSlotAngleAbs(abs),
          alignment: Alignment.center,
          child: _maybeTooltip(
            item.tooltip,
            Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: item.onTap,
                child: Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.itemBackgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: widget.brandColor.withValues(alpha: isCenterSlot ? 0.55 : 0.28),
                        blurRadius: isCenterSlot ? 16 : 10,
                        spreadRadius: isCenterSlot ? 1 : 0,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(item.icon, color: widget.iconColor, size: 24),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlotPageLabel(BuildContext context, int j, double slotDeg) {
    final item = widget.items[_itemIndexAtSlot(j)];
    final abs = slotDeg.abs();
    final o = _offsetForUserAngleDeg(slotDeg);
    final d = widget.itemDiameter;
    final name = item.pageName;

    if (name == null || name.isEmpty || !_showsPageLabel(abs)) {
      return const SizedBox.shrink();
    }

    final labelLeft = o.dx - d / 2 - _pageLabelMaxWidth - _pageLabelGap;

    return Positioned(
      left: labelLeft.clamp(8.0, widget.size.width - _pageLabelMaxWidth - 8),
      top: (o.dy - d / 2).clamp(0.0, widget.size.height - d),
      width: _pageLabelMaxWidth,
      height: d,
      child: IgnorePointer(
        child: Opacity(
          opacity: _opacityForSlotAngleAbs(abs),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: BoxConstraints(maxWidth: _pageLabelMaxWidth),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: widget.itemBackgroundColor,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: widget.brandColor.withValues(alpha: 0.28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.brandColor.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: widget.iconColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.15,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _maybeTooltip(String? tip, Widget child) {
    if (tip != null && tip.isNotEmpty) {
      return Tooltip(message: tip, child: child);
    }
    return child;
  }
}

/// Left semicircle **ring** ∪ **vertical strip** to [panelRight], minus inner hole — so the
/// panel can run flush to the screen edge (a plain left pie would cut off the ring on the
/// right of the pivot and leave a gap before the bezel).
class _DialRingClipper extends CustomClipper<Path> {
  _DialRingClipper({
    required this.center,
    required this.outerRadius,
    required this.innerRadius,
    required this.panelRight,
  });

  final Offset center;
  final double outerRadius;
  final double innerRadius;
  final double panelRight;

  @override
  Path getClip(Size size) {
    final outerRect = Rect.fromCircle(center: center, radius: outerRadius);

    final leftPie = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(outerRect, math.pi / 2, math.pi, false)
      ..close();

    final strip = Path()
      ..addRect(
        Rect.fromLTRB(
          center.dx,
          center.dy - outerRadius,
          panelRight,
          center.dy + outerRadius,
        ),
      );

    final outerShape = Path.combine(PathOperation.union, leftPie, strip);

    if (innerRadius <= 0 || innerRadius >= outerRadius) {
      return outerShape;
    }

    final innerHole = Path()..addOval(Rect.fromCircle(center: center, radius: innerRadius));
    return Path.combine(PathOperation.difference, outerShape, innerHole);
  }

  @override
  bool shouldReclip(covariant _DialRingClipper oldClipper) {
    return oldClipper.center != center ||
        oldClipper.outerRadius != outerRadius ||
        oldClipper.innerRadius != innerRadius ||
        oldClipper.panelRight != panelRight;
  }
}
