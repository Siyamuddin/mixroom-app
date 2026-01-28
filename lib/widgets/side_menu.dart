// lib/widgets/side_menu.dart
import 'package:flutter/material.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/screens/home.dart';
import 'package:provider/provider.dart';
import '../screens/video_editor.dart';
import '../screens/effects.dart';
import '../screens/account.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:juce_audio_engine/juce_audio_engine.dart';

class SideMenu extends StatelessWidget {
  const SideMenu({Key? key}) : super(key: key);

  Future<void> _launchStore(BuildContext context) async {
    const url = 'https://www.mixroom.ai/';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication, // Opens in browser
        );
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to open store: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      // Wrap SideMenu with Consumer
      builder: (context, localeProvider, child) {
        return Drawer(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    // DrawerHeader(
                    //   decoration: BoxDecoration(color: Theme.of(context).primaryColor),
                    //   child: const Text(
                    //     'Menu',
                    //     style: TextStyle(color: Colors.white, fontSize: 24),
                    //   ),
                    // ),
                    ListTile(
                      leading: const Icon(Icons.edit),
                      title: Text(L10n.translate(context, 'Editor')),
                      onTap: () async {
                        await JuceAudioEngine.shutdown();
                        Navigator.pop(context);
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomeScreen()));
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.store),
                      title: Text(L10n.translate(context, 'Store')),
                      onTap: () => _launchStore(context),
                    ),
                    // ListTile(
                    //   leading: const Icon(Icons.slideshow),
                    //   title: const Text('Effects'),
                    //   onTap: () {
                    //     Navigator.pop(context);
                    //     Navigator.pushReplacement(
                    //       context,
                    //       MaterialPageRoute(builder: (context) => const EffectsScreen()),
                    //     );
                    //   },
                    // ),
                    // ListTile(
                    //   leading: const Icon(Icons.account_circle),
                    //   title: const Text('Account'),
                    //   onTap: () {
                    //     Navigator.pop(context);
                    //     Navigator.pushReplacement(
                    //       context,
                    //       MaterialPageRoute(builder: (context) => const AccountScreen()),
                    //     );
                    //   },
                    // ),
                    // Add more ListTiles here if you have more menu items
                  ],
                ),
              ),
              const Divider(), // Optional: Adds a visual separator
              _buildLanguageSelector(context),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Text(
                      //   '© Mixroom',
                      //   style: TextStyle(fontSize: 12, color: Colors.grey),
                      // ),
                      Text(L10n.translate(context, '© Mixroom'), style: TextStyle(fontSize: 12, color: Colors.grey)),
                      // Text(
                      //   'Powered by Mixroom',
                      //   style: TextStyle(fontSize: 12, color: Colors.grey),
                      // ),
                      // Text(L10n.translate(context, 'Powered by Mixroom'), style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _buildLanguageSelector(BuildContext context) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    child: DropdownButton<Locale>(
      value: Provider.of<LocaleProvider>(context).locale ?? L10n.getDeviceLocale(context),
      isExpanded: true,
      items: L10n.supportedLocales.map((locale) {
        return DropdownMenuItem(
          value: locale,
          child: Row(
            children: [
              _getFlag(locale.languageCode),
              const SizedBox(width: 12),
              Text(locale.languageCode.toUpperCase(), style: const TextStyle(fontSize: 16)),
            ],
          ),
        );
      }).toList(),
      onChanged: (locale) {
        if (locale != null) {
          L10n.setLocale(context, locale);
          Navigator.pop(context);
        }
      },
    ),
  );
}

Widget _getFlag(String languageCode) {
  final flags = {
    'en': '🇺🇸', // US flag for English
    'ko': '🇰🇷', // South Korea flag
    'zh': '🇨🇳', // China flag
    'ja': '🇯🇵', // Japan flag
  };
  return Text(flags[languageCode] ?? '🌐', style: const TextStyle(fontSize: 24));
}
