/// Checks if a user has an active premium subscription, mirroring the web backend check.
/// [settingsRow] should be a map from `user_settings` containing `is_premium` and `premium_expires_at`.
bool isPremiumActive(Map<String, dynamic>? settingsRow) {
  if (settingsRow == null) return false;
  if (settingsRow['is_premium'] != true) return false;
  final expiresAtStr = settingsRow['premium_expires_at']?.toString();
  if (expiresAtStr == null || expiresAtStr.isEmpty) return true;
  final expiresAt = DateTime.tryParse(expiresAtStr);
  if (expiresAt == null) return true;
  return expiresAt.isAfter(DateTime.now());
}
