/// Build-time configuration for optional integrations.
class AppConfig {
  AppConfig._();

  /// Production web app (Next.js) origin **without** trailing slash.
  /// Used to call `/api/admin/accounts` for creating admins/partners and role changes.
  /// Override at build time for staging: `--dart-define=WEB_APP_BASE_URL=https://...`
  static const String webAppBaseUrl = String.fromEnvironment(
    'WEB_APP_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static bool get hasWebAppForAdminApi => webAppBaseUrl.trim().isNotEmpty;

  /// Public-facing admin contact (mirrors the web app — see
  /// `manavizha/app/referral-partner/settings/page.tsx`). Surfaced to users
  /// when sign up fails because of an existing email/phone, etc.
  static const String adminEmail = String.fromEnvironment(
    'ADMIN_EMAIL',
    defaultValue: 'arjun.rksaravanan@gmail.com',
  );

  static const String adminPhone = String.fromEnvironment(
    'ADMIN_PHONE',
    defaultValue: '+91 8072734996',
  );
}
