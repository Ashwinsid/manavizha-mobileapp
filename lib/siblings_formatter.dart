String? formatSiblings(Map<String, dynamic>? fm) {
  if (fm == null) return null;
  final countStr = fm['siblings']?.toString().trim();
  final details = fm['sibling_details'] as List?;
  if (details != null && details.isNotEmpty) {
    int brothers = details.where((e) => e['type'] == 'brother').length;
    int sisters = details.where((e) => e['type'] == 'sister').length;
    List<String> parts = [];
    if (brothers > 0) parts.add('$brothers Brother${brothers > 1 ? 's' : ''}');
    if (sisters > 0) parts.add('$sisters Sister${sisters > 1 ? 's' : ''}');
    if (parts.isNotEmpty) return parts.join(', ');
  }
  if (countStr != null && countStr.isNotEmpty) return countStr;
  return null;
}
