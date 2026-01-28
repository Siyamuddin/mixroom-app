import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:mixroom/screens/video_editor2.dart';
import 'package:provider/provider.dart';
import 'video_editor.dart';
import 'package:mixroom/widgets/main_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  void _showNotificationDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color.fromARGB(255, 36, 36, 36),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return SizedBox(
          height: 300,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  L10n.translate(context, 'Notifications'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Divider(color: Colors.white24),
                SizedBox(height: 12),
                Text(L10n.translate(context, 'No new notifications'), style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // return Scaffold(
    //   backgroundColor: const Color(0xFF141414),
    //   body: _HomePage(),
    //   drawer: const MainDrawer(),
    // );
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, child) {
        return Scaffold(
          backgroundColor: const Color(0xFF141414),
          body: _HomePage(), // 👈 this will rebuild when locale changes
          drawer: const MainDrawer(),
        );
      },
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background Image with blur and dark overlay
        Positioned.fill(
          child: Stack(
            children: [
              Image.asset(
                'assets/home_background.png',
                fit: BoxFit.cover,
                height: double.infinity,
                width: double.infinity,
              ),
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: Container(color: Colors.black.withOpacity(0.7)),
              ),
            ],
          ),
        ),

        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top bar
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Builder(
                                builder: (context) => IconButton(
                                  icon: const Icon(Icons.menu, color: Colors.white),
                                  onPressed: () {
                                    Scaffold.of(context).openDrawer();
                                  },
                                ),
                              ),
                              Image.asset('assets/mixroom_logo_white.png', height: 24, width: 24),
                              IconButton(
                                icon: const Icon(Icons.notifications_none, color: Colors.white),
                                onPressed: () {
                                  final state = context.findAncestorStateOfType<_HomeScreenState>();
                                  state?._showNotificationDrawer();
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          Center(
                            child: Text(
                              L10n.translate(context, 'Welcome to Mixroom'), //Mixroom',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Search bar
                          NeumorphicButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  backgroundColor: const Color(0xFF2C2C2C),
                                  title: Text(
                                    L10n.translate(context, 'Coming Soon'),
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  content: Text(
                                    L10n.translate(context, 'Search feature coming soon!'),
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('OK'), //, style: TextStyle(color: Color(0xFF2F44FF))),
                                    ),
                                  ],
                                ),
                              );
                            },
                            style: NeumorphicStyle(
                              depth: 0,
                              intensity: 0.3,
                              color: Colors.white.withOpacity(0.1),
                              boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(20)),
                              shadowDarkColor: Colors.black,
                              shadowLightColor: Colors.grey.shade800,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Icon(Icons.search, color: Colors.white70),
                                SizedBox(width: 8),
                                // Text(
                                //   L10n.translate(context, 'Title / Artist / Genre / etc...'),
                                //   style: TextStyle(color: Colors.white70),
                                // ),
                                Expanded(
                                  // 👈 this forces the text to respect available width
                                  child: Text(
                                    L10n.translate(context, 'Title / Artist / Genre / etc...'),
                                    style: const TextStyle(color: Colors.white70),
                                    maxLines: 1, // keep to one line
                                    overflow: TextOverflow.ellipsis, // show "…" if too long
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Neumorphic Explore tile
                          NeumorphicButton(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  backgroundColor: const Color(0xFF2C2C2C),
                                  title: Text(
                                    L10n.translate(context, 'Coming Soon'),
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  content: Text(
                                    L10n.translate(context, 'Explore feature coming soon!'),
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('OK'), //, style: TextStyle(color: Color(0xFF2F44FF))),
                                    ),
                                  ],
                                ),
                              );
                            },
                            style: NeumorphicStyle(
                              depth: 2,
                              intensity: 0.7,
                              surfaceIntensity: 0.2,
                              color: const Color(0xFF1A1A1A),
                              boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(20)),
                              shadowDarkColor: Colors.black,
                              shadowLightColor: Colors.grey.shade800,
                            ),
                            padding: EdgeInsets.zero,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Image.asset(
                                    'assets/explore_guitar.png',
                                    width: double.infinity,
                                    height: 160,
                                    fit: BoxFit.cover,
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    color: Colors.black.withOpacity(0),
                                    child: Text(
                                      L10n.translate(context, 'Explore'),
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Mode buttons
                          Row(
                            children: [
                              Expanded(
                                child: _ModeCard(title: "Basic", mode: "Basic", icon: Icons.smart_toy),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: _ModeCard(title: "Pro", mode: "Pro", icon: Icons.grid_view_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String mode;
  final IconData icon;

  const _ModeCard({required this.title, required this.mode, required this.icon});

  @override
  Widget build(BuildContext context) {
    return NeumorphicButton(
      onPressed: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => VideoEditorScreen2(mode: mode),
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
        );
      },
      style: NeumorphicStyle(
        color: const Color(0xFF2F44FF),
        depth: 2, // reduced from 4
        intensity: 0.6, // reduced for softer lighting
        surfaceIntensity: 0.1, // prevents glow effect
        boxShape: NeumorphicBoxShape.roundRect(BorderRadius.circular(30)),
        shadowDarkColor: Colors.black,
        shadowLightColor: Colors.white10,
      ),
      padding: EdgeInsets.zero,
      child: SizedBox(
        // height: 172,
        height: MediaQuery.of(context).size.width > 600 ? 300 : 172,
        width: 165, //double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  mode == "Basic" ? 'assets/basic_icon.png' : 'assets/pro_icon.png',
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(12)),
                  ),
                  child: Text(
                    L10n.translate(context, title),
                    style: TextStyle(
                      color: mode == "Basic" ? Colors.white : const Color(0xFF2F44FF),
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
