import 'package:flutter/material.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class LegalPrivacyCenterScreen extends StatefulWidget {
  const LegalPrivacyCenterScreen({super.key});

  @override
  State<LegalPrivacyCenterScreen> createState() => _LegalPrivacyCenterScreenState();
}

class _LegalPrivacyCenterScreenState extends State<LegalPrivacyCenterScreen> {
  static const String _analyticsPrefKey = 'mixroom.privacy.analytics_diagnostics.v1';
  static const String _recommendationsPrefKey = 'mixroom.privacy.personalized_recommendations.v1';
  static const String _productEmailsPrefKey = 'mixroom.privacy.product_emails.v1';

  static const String _privacyEmail = 'privacy@mixroom.ai';
  static const String _supportEmail = 'support@mixroom.ai';

  bool _loadingPreferences = true;
  bool _analyticsEnabled = true;
  bool _recommendationsEnabled = true;
  bool _productEmailsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _analyticsEnabled = prefs.getBool(_analyticsPrefKey) ?? true;
      _recommendationsEnabled = prefs.getBool(_recommendationsPrefKey) ?? true;
      _productEmailsEnabled = prefs.getBool(_productEmailsPrefKey) ?? true;
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
    } catch (_) {
      if (!mounted) return;
      setState(() => applyLocalValue(!value));
      _showMessage(L10n.translate(context, 'Could not save preference. Please retry.'));
    }
  }

  Future<void> _launchUri(
    Uri uri, {
    LaunchMode mode = LaunchMode.externalApplication,
  }) async {
    final launched = await launchUrl(uri, mode: mode);
    if (!launched && mounted) {
      _showMessage(L10n.translate(context, 'Could not open this link on your device right now.'));
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(L10n.translate(context, 'Delete account permanently?')),
        content: Text(
          L10n.translate(context, 'This removes your account and signs you out. This action cannot be undone.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L10n.translate(context, 'Cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8C3838),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(L10n.translate(context, 'Delete')),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    await context.read<AuthService>().deleteAccount();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = context.watch<AuthService>().isBusy;
    final media = MediaQuery.of(context);
    final bottomInset = media.viewPadding.bottom > media.systemGestureInsets.bottom
        ? media.viewPadding.bottom
        : media.systemGestureInsets.bottom;

    return Scaffold(
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(86),
        child: _LegalPrivacyTopBar(),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 24 + bottomInset),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Text(
              L10n.translate(
                  context, 'Review legal documents, control privacy settings, and submit data-rights requests here.'),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.35,
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
                subtitle: L10n.translate(context, 'How Mixroom collects, uses, and shares information.'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyDocumentScreen(),
                    ),
                  );
                },
              ),
              _ActionItem(
                icon: Icons.description_outlined,
                title: L10n.translate(context, 'Terms of Service'),
                subtitle: L10n.translate(context, 'Rules for using Mixroom and user content.'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TermsOfServiceDocumentScreen(),
                    ),
                  );
                },
              ),
              _ActionItem(
                icon: Icons.integration_instructions_outlined,
                title: L10n.translate(context, 'Open-source licenses'),
                subtitle: L10n.translate(context, 'View software licenses used by this app.'),
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
            subtitle: L10n.translate(context, 'You can change these preferences at any time from this screen.'),
            children: [
              _ToggleItem(
                icon: Icons.analytics_outlined,
                title: L10n.translate(context, 'Usage analytics and crash diagnostics'),
                subtitle: L10n.translate(context, 'Helps improve stability and product quality.'),
                value: _analyticsEnabled,
                enabled: !_loadingPreferences && !isBusy,
                onChanged: (next) => _saveToggle(
                  key: _analyticsPrefKey,
                  value: next,
                  applyLocalValue: (value) => _analyticsEnabled = value,
                ),
              ),
              _ToggleItem(
                icon: Icons.auto_awesome_outlined,
                title: L10n.translate(context, 'Personalized recommendations'),
                subtitle: L10n.translate(context, 'Uses activity signals to tailor tips and suggestions.'),
                value: _recommendationsEnabled,
                enabled: !_loadingPreferences && !isBusy,
                onChanged: (next) => _saveToggle(
                  key: _recommendationsPrefKey,
                  value: next,
                  applyLocalValue: (value) => _recommendationsEnabled = value,
                ),
              ),
              _ToggleItem(
                icon: Icons.mark_email_read_outlined,
                title: L10n.translate(context, 'Product updates and marketing email'),
                subtitle: L10n.translate(context, 'Receive release notes, offers, and feature announcements.'),
                value: _productEmailsEnabled,
                enabled: !_loadingPreferences && !isBusy,
                onChanged: (next) => _saveToggle(
                  key: _productEmailsPrefKey,
                  value: next,
                  applyLocalValue: (value) => _productEmailsEnabled = value,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: L10n.translate(context, 'Your Data Rights'),
            children: [
              _ActionItem(
                icon: Icons.inventory_2_outlined,
                title: L10n.translate(context, 'Request my data export'),
                subtitle: L10n.translate(context, 'Email request for a copy of your data.'),
                onTap: _requestDataExport,
              ),
              _ActionItem(
                icon: Icons.edit_note_outlined,
                title: L10n.translate(context, 'Request data correction or deletion'),
                subtitle: L10n.translate(context, 'Email request for correction or erasure.'),
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
                title: L10n.translate(context, 'Delete account permanently'),
                subtitle: L10n.translate(context, 'Removes your account and signs you out.'),
                iconColor: const Color(0xFFFFA4A4),
                titleColor: const Color(0xFFFFD4D4),
                onTap: isBusy ? null : _confirmDeleteAccount,
              ),
            ],
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withOpacity(0.07)),
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
        output.add(_SectionDivider());
      }
    }
    return output;
  }
}

class _LegalPrivacyTopBar extends StatelessWidget {
  const _LegalPrivacyTopBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF1B3156),
                Color(0xFF132640),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: L10n.translate(context, 'Back'),
                onPressed: () => Navigator.of(context).maybePop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.white.withOpacity(0.10)),
                  ),
                ),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      L10n.translate(context, 'Legal & Privacy'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      L10n.translate(context, 'Controls, documents, and requests'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 18,
                color: disabled ? Colors.white30 : iconColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: disabled ? Colors.white38 : titleColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: disabled ? Colors.white30 : Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: disabled ? Colors.white24 : Colors.white54,
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
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: enabled ? const Color(0xFFA4C2FF) : Colors.white30,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.white38,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: enabled ? Colors.white70 : Colors.white30,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: Colors.white.withOpacity(0.07));
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
          body: 'For privacy requests, contact privacy@mixroom.ai. For support, contact support@mixroom.ai.',
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
          body: 'By creating an account or using Mixroom, you agree to these Terms and any policies referenced here.',
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
          body: 'Legal questions can be sent to privacy@mixroom.ai or support@mixroom.ai.',
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

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewPadding.bottom > media.systemGestureInsets.bottom
        ? media.viewPadding.bottom
        : media.systemGestureInsets.bottom;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Last updated: $updatedAt',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  intro,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...sections.map(
            (section) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.heading,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      section.body,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
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
