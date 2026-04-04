/// Build-time configuration for optional integrations.
class AppConfig {
  AppConfig._();

  /// Production web app (Next.js) origin **without** trailing slash.
  /// Used to call `/api/admin/accounts` for creating admins/partners and role changes.
  /// Override at build time for staging: `--dart-define=WEB_APP_BASE_URL=https://...`
  static const String webAppBaseUrl = String.fromEnvironment(
    'WEB_APP_BASE_URL',
    defaultValue: 'https://manavizha.com',
  );

  static bool get hasWebAppForAdminApi => webAppBaseUrl.trim().isNotEmpty;
}
