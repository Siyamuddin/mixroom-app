import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:mixroom/screens/home.dart';
import 'package:mixroom/screens/account.dart';
import 'package:mixroom/screens/projects.dart';
import 'package:mixroom/screens/presets.dart';
import 'package:mixroom/screens/uploads.dart';
import 'package:mixroom/screens/about.dart';
import 'package:mixroom/screens/howto.dart';
import 'package:mixroom/screens/notice.dart';
import 'package:provider/provider.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/l10n/l10n.dart';

class MainDrawer extends StatelessWidget {
  const MainDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          // Glass background
          ClipRRect(
            borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.white.withOpacity(0.08)),
            ),
          ),

          // Menu content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white, size: 32),
                  ),
                  // const SizedBox(height: 12),
                  // const Text(
                  //   "Welcome back,\nssonnyisrollin",
                  //   style: TextStyle(
                  //     color: Colors.white,
                  //     fontSize: 16,
                  //     height: 1.4,
                  //   ),
                  // ),
                  const SizedBox(height: 24),
                  _buildNavIcon(context, Icons.home, L10n.translate(context, 'Home'), const HomeScreen()),
                  const SizedBox(height: 6),
                  _buildNavIcon(context, Icons.work, L10n.translate(context, 'Projects'), const ProjectsScreen()),
                  const SizedBox(height: 6),
                  _buildNavIcon(context, Icons.tune, L10n.translate(context, 'Presets'), const PresetsScreen()),
                  const SizedBox(height: 6),
                  _buildNavIcon(context, Icons.cloud_upload, L10n.translate(context, 'Uploads'), const UploadsScreen()),
                  const SizedBox(height: 6),
                  _buildNavIcon(
                    context,
                    Icons.account_circle,
                    L10n.translate(context, 'My Account'),
                    const AccountScreen(),
                  ),
                  const Divider(color: Colors.white30, height: 32),
                  _buildNavIcon(context, Icons.info_outline, L10n.translate(context, 'About'), const AboutScreen()),
                  const SizedBox(height: 10),
                  _buildNavIcon(
                    context,
                    Icons.help_outline,
                    L10n.translate(context, 'How to Use'),
                    const HowtoScreen(),
                  ),
                  const SizedBox(height: 10),
                  _buildNavIcon(
                    context,
                    Icons.notifications_none,
                    L10n.translate(context, 'Notice'),
                    const NoticeScreen(),
                  ),
                  const Spacer(),
                  _buildLanguageSelector(context),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      // TODO: Handle sign out
                    },
                    child: _buildTextItem(L10n.translate(context, 'Sign Out'), isDestructive: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavIcon(BuildContext context, IconData icon, String label, Widget screen) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop(); // close drawer first

        // TODO: add a check for the route name. if it matches don't take any action
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildTextItem(String label, {bool isDestructive = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(label, style: TextStyle(color: isDestructive ? Colors.redAccent : Colors.white70, fontSize: 15)),
    );
  }

  Widget _buildLanguageSelector(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    final currentLocale = localeProvider.locale ?? L10n.getDeviceLocale(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Container(
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Locale>(
            value: currentLocale,
            isExpanded: true,
            dropdownColor: const Color(0xFF1E1E1E),
            style: const TextStyle(color: Colors.white),
            iconEnabledColor: Colors.white,
            items: L10n.supportedLocales.map((locale) {
              return DropdownMenuItem(
                value: locale,
                child: Row(
                  children: [
                    _getFlag(locale.languageCode),
                    const SizedBox(width: 12),
                    Text(locale.languageCode.toUpperCase()),
                  ],
                ),
              );
            }).toList(),
            // onChanged: (locale) {
            //   if (locale != null) {
            //     L10n.setLocale(context, locale);
            //     Navigator.pop(context); // close drawer after selection
            //   }
            // },
            onChanged: (locale) {
              if (locale != null) {
                L10n.setLocale(context, locale);

                Navigator.of(context).pushAndRemoveUntil(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => HomeScreen(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      const beginScale = 0.96;
                      const endScale = 1.0;
                      const curve = Curves.easeOutCubic;

                      final tween = Tween<double>(begin: beginScale, end: endScale).chain(CurveTween(curve: curve));
                      final fadeTween = Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));

                      return FadeTransition(
                        opacity: animation.drive(fadeTween),
                        child: ScaleTransition(scale: animation.drive(tween), child: child),
                      );
                    },
                    transitionDuration: const Duration(milliseconds: 300),
                  ),
                  (route) => false, // remove all previous routes
                );
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _getFlag(String languageCode) {
    const flags = {'en': '🇺🇸', 'ko': '🇰🇷', 'zh': '🇨🇳', 'ja': '🇯🇵'};
    return Text(flags[languageCode] ?? '🌐', style: const TextStyle(fontSize: 20));
  }
}
