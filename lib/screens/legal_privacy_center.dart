import 'package:flutter/material.dart';
import 'package:mixroom/config/legal_config.dart';
import 'package:mixroom/core/analytics/analytics_service.dart';
import 'package:mixroom/core/crash_reporting/crash_reporting_service.dart';
import 'package:mixroom/core/privacy/privacy_preferences.dart';
import 'package:mixroom/helpers/app_user_service.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/widgets/app_responsive_body.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';
import 'package:mixroom/widgets/delete_account_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class LegalPrivacyCenterScreen extends StatefulWidget {
  const LegalPrivacyCenterScreen({super.key});

  @override
  State<LegalPrivacyCenterScreen> createState() =>
      _LegalPrivacyCenterScreenState();
}

class _LegalPrivacyCenterScreenState extends State<LegalPrivacyCenterScreen> {
  static const String _analyticsPrefKey =
      PrivacyPreferences.analyticsAndCrashDiagnosticsKey;
  static const String _recommendationsPrefKey =
      'mixroom.privacy.personalized_recommendations.v1';
  static const String _productEmailsPrefKey =
      'mixroom.privacy.product_emails.v1';

  static const String _privacyEmail = 'privacy@mixroom.ai';
  static const String _supportEmail = 'support@mixroom.ai';

  bool _loadingPreferences = true;
  bool _analyticsEnabled = false;
  bool _recommendationsEnabled = false;
  bool _productEmailsEnabled = false;
  bool _savingProductEmails = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final auth = context.read<AuthService>();
    final appUser = context.read<AppUserService>();
    if (auth.isSignedIn && appUser.supportsRemoteProfileEdits) {
      try {
        await appUser.refresh(force: true);
      } catch (_) {
        // Fall back to cached or local values if the refresh fails.
      }
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _analyticsEnabled = appUser.current?.telemetryEnabled ??
          (prefs.getBool(_analyticsPrefKey) ?? true);
      _recommendationsEnabled = prefs.getBool(_recommendationsPrefKey) ?? false;
      _productEmailsEnabled = appUser.current?.newsletterOptIn ??
          (prefs.getBool(_productEmailsPrefKey) ?? false);
      _loadingPreferences = false;
    });
  }

  Future<void> _saveToggle({
    required String key,
    required bool value,
    required void Function(bool nextValue) applyLocalValue,
  }) async {
    setState(() => applyLocalValue(value));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
      if (key == _analyticsPrefKey) {
        await AnalyticsService.instance.setCollectionEnabled(value);
        await CrashReportingService.instance.setCollectionEnabled(value);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => applyLocalValue(!value));
      _showMessage(
        L10n.translate(context, 'Could not save preference. Please retry.'),
      );
    }
  }

  Future<void> _saveTelemetryToggle(bool value) async {
    final auth = context.read<AuthService>();
    final appUser = context.read<AppUserService>();
    final previousValue = auth.isSignedIn && appUser.supportsRemoteProfileEdits
        ? (appUser.current?.telemetryEnabled ?? _analyticsEnabled)
        : _analyticsEnabled;

    setState(() {
      _analyticsEnabled = value;
    });

    try {
      if (auth.isSignedIn && appUser.supportsRemoteProfileEdits) {
        await appUser.updateTelemetryPreference(
          telemetryEnabled: value,
        );
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_analyticsPrefKey, value);
        await AnalyticsService.instance.setCollectionEnabled(value);
        await CrashReportingService.instance.setCollectionEnabled(value);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _analyticsEnabled = previousValue;
      });
      _showMessage(
        L10n.translate(
          context,
          'Could not update telemetry preference. Please retry.',
        ),
      );
    }
  }

  Future<void> _saveProductEmailsToggle(bool value) async {
    final auth = context.read<AuthService>();
    final appUser = context.read<AppUserService>();
    final previousValue = auth.isSignedIn && appUser.supportsRemoteProfileEdits
        ? (appUser.current?.newsletterOptIn ?? _productEmailsEnabled)
        : _productEmailsEnabled;

    setState(() {
      _productEmailsEnabled = value;
      _savingProductEmails = true;
    });

    try {
      if (auth.isSignedIn && appUser.supportsRemoteProfileEdits) {
        await appUser.updateNewsletterPreference(
          newsletterOptIn: value,
          localeCode: Localizations.localeOf(context).languageCode,
        );
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_productEmailsPrefKey, value);
        await PrivacyPreferences.setProductEmailsEnabled(value);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _productEmailsEnabled = previousValue;
      });
      _showMessage(
        L10n.translate(
          context,
          'Could not update marketing email preference. Please retry.',
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingProductEmails = false;
        });
      }
    }
  }

  Future<void> _launchUri(
    Uri uri, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    final launched = await launchUrl(uri, mode: mode);
    if (!launched && mounted) {
      _showMessage(
        L10n.translate(
          context,
          'Could not open this link on your device right now.',
        ),
      );
    }
  }

  Future<void> _openEmail({
    required String to,
    required String subject,
    required String body,
  }) {
    final uri = Uri(
      scheme: 'mailto',
      path: to,
      queryParameters: <String, String>{
        'subject': subject,
        'body': body,
      },
    );
    return _launchUri(uri, mode: LaunchMode.platformDefault);
  }

  Future<void> _requestDataExport() {
    return _openEmail(
      to: _privacyEmail,
      subject: 'Data export request',
      body: 'Hello Mixroom Privacy Team,\n\n'
          'I would like to request a copy of my personal data.\n\n'
          'Account email: \n'
          'Full name: \n\n'
          'Thank you.',
    );
  }

  Future<void> _requestDataCorrectionOrDeletion() {
    return _openEmail(
      to: _privacyEmail,
      subject: 'Data correction/deletion request',
      body: 'Hello Mixroom Privacy Team,\n\n'
          'I would like to request a correction or deletion of my personal data.\n\n'
          'Account email: \n'
          'Request details: \n\n'
          'Thank you.',
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final ok = await showDeleteAccountSheet(
      context,
      auth: context.read<AuthService>(),
    );

    if (ok != true || !mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final appUser = context.watch<AppUserService>();
    final effectiveProductEmailsEnabled = !_savingProductEmails &&
            auth.isSignedIn &&
            appUser.supportsRemoteProfileEdits &&
            appUser.current != null
        ? appUser.current!.newsletterOptIn
        : _productEmailsEnabled;
    final isBusy = auth.isBusy || appUser.isLoading || _savingProductEmails;
    final media = MediaQuery.of(context);
    final bottomInset =
        media.viewPadding.bottom > media.systemGestureInsets.bottom
            ? media.viewPadding.bottom
            : media.systemGestureInsets.bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: MixroomShellBackground()),
          SafeArea(
            bottom: false,
            child: AppResponsiveBody(
              maxWidth: 920,
              expandToHeight: true,
              child: ListView(
                padding: EdgeInsets.fromLTRB(14, 10, 14, 24 + bottomInset),
                children: [
                  _ShellPageTopBar(
                    title: L10n.translate(context, 'Legal & Privacy'),
                    subtitle: L10n.translate(
                      context,
                      'Controls, documents, and requests',
                    ),
                  ),
                  const SizedBox(height: 12),
                  MixroomShellSurface(
                    radius: 26,
                    strong: true,
                    color: const Color.fromRGBO(244, 244, 244, 0.10),
                    padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                    child: Text(
                      L10n.translate(
                        context,
                        'Review legal documents, control privacy settings, and submit data-rights requests here.',
                      ),
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: L10n.translate(context, 'Documents'),
                    children: [
                      _ActionItem(
                        icon: Icons.privacy_tip_outlined,
                        title: L10n.translate(context, 'Privacy Policy'),
                        subtitle: L10n.translate(
                          context,
                          'How Mixroom collects, uses, and shares information.',
                        ),
                        onTap: () =>
                            _launchUri(Uri.parse(LegalConfig.privacyUrl)),
                      ),
                      _ActionItem(
                        icon: Icons.description_outlined,
                        title: L10n.translate(context, 'Terms of Service'),
                        subtitle: L10n.translate(
                          context,
                          'Rules for using Mixroom and user content.',
                        ),
                        onTap: () =>
                            _launchUri(Uri.parse(LegalConfig.termsUrl)),
                      ),
                      _ActionItem(
                        icon: Icons.groups_outlined,
                        title: L10n.translate(context, 'Subprocessors'),
                        subtitle: L10n.translate(
                          context,
                          'See third-party service providers that process data on Mixroom\'s behalf.',
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const SubprocessorsDocumentScreen(),
                            ),
                          );
                        },
                      ),
                      _ActionItem(
                        icon: Icons.integration_instructions_outlined,
                        title: L10n.translate(
                          context,
                          'Open-source licenses',
                        ),
                        subtitle: L10n.translate(
                          context,
                          'View software licenses used by this app.',
                        ),
                        onTap: () {
                          showLicensePage(
                            context: context,
                            applicationName: 'Mixroom',
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: L10n.translate(context, 'Privacy Controls'),
                    subtitle: L10n.translate(
                      context,
                      'You can change these preferences at any time from this screen.',
                    ),
                    children: [
                      _ToggleItem(
                        icon: Icons.analytics_outlined,
                        title: L10n.translate(
                          context,
                          'Optional analytics and diagnostics',
                        ),
                        subtitle: L10n.translate(
                          context,
                          'Share app interaction events and diagnostics to help improve Mixroom quality and product decisions.',
                        ),
                        value: _analyticsEnabled,
                        enabled: !_loadingPreferences && !isBusy,
                        onChanged: _saveTelemetryToggle,
                      ),
                      _ToggleItem(
                        icon: Icons.auto_awesome_outlined,
                        title: L10n.translate(
                          context,
                          'Personalized recommendations',
                        ),
                        subtitle: L10n.translate(
                          context,
                          'Uses activity signals to tailor tips and suggestions.',
                        ),
                        value: _recommendationsEnabled,
                        enabled: !_loadingPreferences && !isBusy,
                        onChanged: (next) => _saveToggle(
                          key: _recommendationsPrefKey,
                          value: next,
                          applyLocalValue: (value) =>
                              _recommendationsEnabled = value,
                        ),
                      ),
                      _ToggleItem(
                        icon: Icons.mark_email_read_outlined,
                        title: L10n.translate(
                          context,
                          'Product updates and marketing email',
                        ),
                        subtitle: L10n.translate(
                          context,
                          'Receive release notes, offers, and feature announcements.',
                        ),
                        value: effectiveProductEmailsEnabled,
                        enabled: !_loadingPreferences && !isBusy,
                        onChanged: _saveProductEmailsToggle,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: L10n.translate(context, 'Your Data Rights'),
                    children: [
                      _ActionItem(
                        icon: Icons.inventory_2_outlined,
                        title:
                            L10n.translate(context, 'Request my data export'),
                        subtitle: L10n.translate(
                          context,
                          'Email request for a copy of your data.',
                        ),
                        onTap: _requestDataExport,
                      ),
                      _ActionItem(
                        icon: Icons.edit_note_outlined,
                        title: L10n.translate(
                          context,
                          'Request data correction or deletion',
                        ),
                        subtitle: L10n.translate(
                          context,
                          'Email request for correction or erasure.',
                        ),
                        onTap: _requestDataCorrectionOrDeletion,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: L10n.translate(context, 'Contact'),
                    children: [
                      _ActionItem(
                        icon: Icons.privacy_tip_outlined,
                        title: L10n.translate(context, 'Privacy contact'),
                        subtitle: _privacyEmail,
                        onTap: () => _openEmail(
                          to: _privacyEmail,
                          subject: 'Privacy inquiry',
                          body: 'Hello Mixroom Privacy Team,\n\n',
                        ),
                      ),
                      _ActionItem(
                        icon: Icons.support_agent_outlined,
                        title: L10n.translate(context, 'Support contact'),
                        subtitle: _supportEmail,
                        onTap: () => _openEmail(
                          to: _supportEmail,
                          subject: 'Support request',
                          body: 'Hello Mixroom Support,\n\n',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    title: L10n.translate(context, 'Danger Zone'),
                    children: [
                      _ActionItem(
                        icon: Icons.delete_forever_outlined,
                        title: L10n.translate(
                          context,
                          'Delete account permanently',
                        ),
                        subtitle: L10n.translate(
                          context,
                          'Removes your account and signs you out.',
                        ),
                        iconColor: const Color(0xFFFFA4A4),
                        titleColor: const Color(0xFFFFD4D4),
                        onTap: isBusy ? null : _confirmDeleteAccount,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellPageTopBar extends StatelessWidget {
  const _ShellPageTopBar({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return MixroomShellSurface(
      radius: 28,
      strong: true,
      color: const Color.fromRGBO(244, 244, 244, 0.12),
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          MixroomShellRoundButton(
            size: 46,
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: Colors.white,
            ),
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    color: Color(0xFFF4F4F4),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return MixroomShellSurface(
      radius: 28,
      strong: true,
      color: const Color.fromRGBO(244, 244, 244, 0.08),
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              color: Color(0xFFF4F4F4),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontFamily: 'Pretendard',
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 10),
          ..._withDividers(children),
        ],
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    if (items.isEmpty) return const [];
    final output = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      output.add(items[i]);
      if (i != items.length - 1) {
        output.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        );
      }
    }
    return output;
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.iconColor = const Color(0xFFA4C2FF),
    this.titleColor = Colors.white,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color iconColor;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 11, 2, 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (disabled ? Colors.white30 : iconColor)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 18,
                  color: disabled ? Colors.white38 : iconColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        color: disabled ? Colors.white38 : titleColor,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontFamily: 'Pretendard',
                          color: disabled
                              ? Colors.white30
                              : Colors.white.withValues(alpha: 0.66),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: disabled
                    ? Colors.white.withValues(alpha: 0.34)
                    : Colors.white.withValues(alpha: 0.68),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleItem extends StatelessWidget {
  const _ToggleItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 11, 2, 11),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (enabled
                      ? const Color(0xFFA4C2FF)
                      : Colors.white.withValues(alpha: 0.30))
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: enabled ? const Color(0xFFA4C2FF) : Colors.white30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    color: enabled ? Colors.white : Colors.white38,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    color: enabled
                        ? Colors.white.withValues(alpha: 0.66)
                        : Colors.white30,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Theme(
            data: Theme.of(context).copyWith(
              switchTheme: SwitchThemeData(
                thumbColor: WidgetStateProperty.resolveWith((states) {
                  if (!enabled) return Colors.white38;
                  return states.contains(WidgetState.selected)
                      ? const Color(0xFFF4F4F4)
                      : const Color(0xFFCCD7E5);
                }),
                trackColor: WidgetStateProperty.resolveWith((states) {
                  if (!enabled) return Colors.white12;
                  return states.contains(WidgetState.selected)
                      ? const Color.fromRGBO(120, 168, 226, 0.64)
                      : const Color.fromRGBO(244, 244, 244, 0.22);
                }),
                trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
              ),
            ),
            child: Switch.adaptive(
              value: value,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }
}

class PrivacyPolicyDocumentScreen extends StatelessWidget {
  const PrivacyPolicyDocumentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalDocumentScreen(
      title: L10n.translate(context, 'Privacy Policy'),
      updatedAt: '2026-02-26',
      intro: 'This policy explains how Mixroom handles personal data in-app.',
      sections: const [
        _LegalSection(
          heading: '1. Information We Collect',
          body:
              'We may collect account information (such as email and profile details), usage analytics, crash diagnostics, and content metadata needed to operate features.',
        ),
        _LegalSection(
          heading: '2. How We Use Data',
          body:
              'Data is used to operate core app functionality, secure accounts, improve product quality, personalize user experience, and communicate essential service updates.',
        ),
        _LegalSection(
          heading: '3. Sharing and Processors',
          body:
              'We may share data with trusted service providers that process data on our behalf (for example authentication, storage, analytics, or support tooling), subject to contractual safeguards.',
        ),
        _LegalSection(
          heading: '4. Retention',
          body:
              'We keep data only as long as needed for business and legal purposes. Retention periods may differ by data type, including backups and security logs.',
        ),
        _LegalSection(
          heading: '5. Your Rights and Choices',
          body:
              'Depending on your region, you may have rights to access, export, correct, delete, or limit use of your personal data. You can submit a request from the Legal & Privacy Center.',
        ),
        _LegalSection(
          heading: '6. Children',
          body:
              'Mixroom is not directed to children under the minimum age required by applicable law without appropriate parental consent and controls.',
        ),
        _LegalSection(
          heading: '7. Contact',
          body:
              'For privacy requests, contact privacy@mixroom.ai. For support, contact support@mixroom.ai.',
        ),
      ],
    );
  }
}

class TermsOfServiceDocumentScreen extends StatelessWidget {
  const TermsOfServiceDocumentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalDocumentScreen(
      title: L10n.translate(context, 'Terms of Service'),
      updatedAt: '2026-02-26',
      intro: 'These terms govern use of Mixroom and related services.',
      sections: const [
        _LegalSection(
          heading: '1. Acceptance',
          body:
              'By creating an account or using Mixroom, you agree to these Terms and any policies referenced here.',
        ),
        _LegalSection(
          heading: '2. Accounts',
          body:
              'You are responsible for your account credentials and activity. Keep login details secure and notify us of unauthorized use.',
        ),
        _LegalSection(
          heading: '3. User Content',
          body:
              'You retain ownership of your content. You grant Mixroom a limited license to host, process, and transmit content solely to provide and improve the service.',
        ),
        _LegalSection(
          heading: '4. Acceptable Use',
          body:
              'You agree not to abuse the service, violate intellectual property rights, distribute malicious content, or use Mixroom in unlawful ways.',
        ),
        _LegalSection(
          heading: '5. Termination',
          body:
              'We may suspend or terminate accounts for violations, fraud, abuse, or legal requirements. You may stop using the service at any time.',
        ),
        _LegalSection(
          heading: '6. Disclaimers and Liability',
          body:
              'Services are provided on an as-is basis to the extent allowed by law. Liability is limited as described in the full legal agreement between you and Mixroom.',
        ),
        _LegalSection(
          heading: '7. Contact',
          body:
              'Legal questions can be sent to privacy@mixroom.ai or support@mixroom.ai.',
        ),
      ],
    );
  }
}

class SubprocessorsDocumentScreen extends StatelessWidget {
  const SubprocessorsDocumentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalDocumentScreen(
      title: L10n.translate(context, 'Subprocessors'),
      updatedAt: '2026-03-25',
      intro:
          'Mixroom uses third-party service providers to operate core app features. These providers process data on our behalf under contractual controls.',
      sections: const [
        _LegalSection(
          heading: 'Amazon Web Services (AWS)',
          body:
              'Purpose: account/authentication infrastructure, APIs, and application hosting. Typical data categories: account identifiers, authentication metadata, service logs, and app data required to deliver Mixroom features.',
        ),
        _LegalSection(
          heading: 'Google (Google Sign-In)',
          body:
              'Purpose: social sign-in and account identity verification when users choose Google login. Typical data categories: basic profile identifiers (such as email and account subject ID) returned by Google authentication flows.',
        ),
        _LegalSection(
          heading: 'Apple (Sign in with Apple)',
          body:
              'Purpose: social sign-in and account identity verification when users choose Apple login. Typical data categories: Apple account subject identifier and email relay/associated account email data provided by Apple auth.',
        ),
        _LegalSection(
          heading: 'Kakao (Kakao Login)',
          body:
              'Purpose: social sign-in and account identity verification when users choose Kakao login. Typical data categories: Kakao account identifier and profile/email fields provided through Kakao authorization.',
        ),
        _LegalSection(
          heading: 'PostHog',
          body:
              'Purpose: product analytics and event telemetry, subject to user privacy toggle settings in-app. Typical data categories: app interaction events, device/app metadata, and aggregated usage signals.',
        ),
        _LegalSection(
          heading: 'Sentry',
          body:
              'Purpose: crash reporting and diagnostics, subject to user privacy toggle settings in-app. Typical data categories: crash stack traces, runtime diagnostics, and device/app version metadata.',
        ),
        _LegalSection(
          heading: 'OpenAI',
          body:
              'Purpose: AI assistant and model-inference features. Typical data categories: prompts/instructions and related context needed to generate assistant responses.',
        ),
        _LegalSection(
          heading: 'Updates',
          body:
              'This list may change as Mixroom adds or removes service providers. Material updates are reflected in-app and in Mixroom privacy documentation.',
        ),
      ],
    );
  }
}

class _LegalDocumentScreen extends StatelessWidget {
  const _LegalDocumentScreen({
    required this.title,
    required this.updatedAt,
    required this.intro,
    required this.sections,
  });

  final String title;
  final String updatedAt;
  final String intro;
  final List<_LegalSection> sections;

  List<Widget> _buildDocumentSections() {
    if (sections.isEmpty) return const [];

    final output = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      output.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.heading,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  color: Color(0xFFF4F4F4),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                section.body,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.42,
                ),
              ),
            ],
          ),
        ),
      );
      if (i != sections.length - 1) {
        output.add(
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),
        );
      }
    }
    return output;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset =
        media.viewPadding.bottom > media.systemGestureInsets.bottom
            ? media.viewPadding.bottom
            : media.systemGestureInsets.bottom;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(child: MixroomShellBackground()),
          SafeArea(
            bottom: false,
            child: AppResponsiveBody(
              maxWidth: 920,
              expandToHeight: true,
              child: ListView(
                padding: EdgeInsets.fromLTRB(14, 10, 14, 24 + bottomInset),
                children: [
                  _ShellPageTopBar(
                    title: title,
                    subtitle: L10n.translate(
                      context,
                      'Legal details and supporting information',
                    ),
                  ),
                  const SizedBox(height: 12),
                  MixroomShellSurface(
                    radius: 28,
                    strong: true,
                    color: const Color.fromRGBO(244, 244, 244, 0.10),
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: Color(0xFFF4F4F4),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Last updated: $updatedAt',
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            color: Colors.white.withValues(alpha: 0.64),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          intro,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            color: Colors.white.withValues(alpha: 0.76),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  MixroomShellSurface(
                    radius: 26,
                    strong: true,
                    color: const Color.fromRGBO(244, 244, 244, 0.08),
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildDocumentSections(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalSection {
  const _LegalSection({
    required this.heading,
    required this.body,
  });

  final String heading;
  final String body;
}
