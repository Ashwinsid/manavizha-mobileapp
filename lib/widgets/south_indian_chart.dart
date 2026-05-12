import 'package:flutter/material.dart';

import '../astrology.dart';

/// One South-Indian Vedic chart (Rasi or Navamsam) — 4x4 grid with the
/// middle 2x2 cells merged into a title block. Mirrors the layout used by
/// `manavizha/components/detailed-horoscope-view.tsx#SouthIndianChart`.
///
/// [planetsByHouse] is keyed by rasi/navamsam index (0..11) and maps to the
/// list of planet abbreviations rendered in that cell. The widget itself
/// stays presentation-only — placement logic lives in the parent screen so
/// the same widget powers both auto-generated and manually-edited charts.
class SouthIndianChart extends StatelessWidget {
  const SouthIndianChart({
    super.key,
    required this.type,
    required this.title,
    required this.planetsByHouse,
    this.centerLines = const <String>[],
    this.editable = false,
    this.onTapHouse,
    this.highlightedHouse,
    this.borderColor = const Color(0xFF7E22CE),
    this.headerBgColor = const Color(0x0D4B0082),
    this.headerTextColor = const Color(0xFF4B0082),
    this.cellAspect = 1.0,
  });

  final String type; // 'Rasi' or 'Navamsam' (used only for labelling)
  final String title;
  final Map<int, List<String>> planetsByHouse;

  /// Centre overlay lines (e.g. nakshatra, dob, tob). Rendered top-to-bottom.
  final List<String> centerLines;

  /// When `true`, cells respond to tap with [onTapHouse] and highlight on
  /// hover/focus. Used by the manual placement editor.
  final bool editable;
  final void Function(int houseIndex)? onTapHouse;
  final int? highlightedHouse;

  final Color borderColor;
  final Color headerBgColor;
  final Color headerTextColor;
  final double cellAspect;

  // 4x4 grid, -1 marks the merged-centre cells.
  static const List<List<int>> _grid = [
    [11, 0, 1, 2],
    [10, -1, -1, 3],
    [9, -1, -1, 4],
    [8, 7, 6, 5],
  ];

  static const _planetColors = <String, Color>{
    'சூ': Color(0xFF4B5563),
    'சந்': Color(0xFF2563EB),
    'செ': Color(0xFFDC2626),
    'பு': Color(0xFF2563EB),
    'வி': Color(0xFFC026D3),
    'சு': Color(0xFF991B1B),
    'சனி': Color(0xFF7E22CE),
    'ரா': Color(0xFF16A34A),
    'கே': Color(0xFF16A34A),
    'ல': Color(0xFF7E22CE),
    'மா': Color(0xFF000000),
    'கு': Color(0xFF0D9488),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: headerBgColor),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: headerTextColor,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(border: Border.all(color: borderColor, width: 2)),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 16,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: cellAspect,
              crossAxisSpacing: 0,
              mainAxisSpacing: 0,
            ),
            itemBuilder: (context, index) {
              final row = index ~/ 4;
              final col = index % 4;
              final rasi = _grid[row][col];
              if (rasi == -1) {
                if (row == 1 && col == 1) return _centerCell();
                return const SizedBox.shrink();
              }
              final occupants = planetsByHouse[rasi] ?? const <String>[];
              return _cell(rasi, occupants);
            },
          ),
        ),
      ],
    );
  }

  Widget _centerCell() {
    return Container(
      // The cell at (1,1) is rendered alone; the (1,2)/(2,1)/(2,2) slots are
      // empty placeholders. We stretch the centre block visually by relying
      // on the surrounding empty cells.
      alignment: Alignment.center,
      decoration: BoxDecoration(border: Border.all(color: borderColor)),
      padding: const EdgeInsets.all(2),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in centerLines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  line,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF6B7280),
                    height: 1.1,
                  ),
                ),
              ),
            const SizedBox(height: 2),
            Text(
              type == 'Rasi' ? 'ராசி' : 'நவாம்சம்',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: Color(0xFF4B5563),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(int rasi, List<String> occupants) {
    final highlight = highlightedHouse == rasi;
    final cell = Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor),
        color: highlight ? const Color(0xFFEEF2FF) : Colors.white,
      ),
      padding: const EdgeInsets.all(2),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 2,
            child: Text(
              rasiNamesTamil[rasi],
              style: TextStyle(
                fontSize: 8,
                color: Colors.black.withValues(alpha: 0.32),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Wrap(
              spacing: 3,
              runSpacing: 2,
              children: [
                for (final abbr in occupants)
                  Text(
                    abbr,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _planetColors[abbr] ?? Colors.black87,
                      height: 1.05,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!editable || onTapHouse == null) return cell;
    return InkWell(
      onTap: () => onTapHouse!(rasi),
      child: cell,
    );
  }
}
