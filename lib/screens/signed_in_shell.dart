import 'package:flutter/material.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/platform_capabilities.dart';
import 'package:mixroom/screens/account.dart';
import 'package:mixroom/screens/login.dart';
import 'package:mixroom/screens/projects.dart';
import 'package:mixroom/screens/video_projects.dart';
import 'package:provider/provider.dart';

class SignedInShell extends StatefulWidget {
  const SignedInShell({super.key});

  @override
  State<SignedInShell> createState() => _SignedInShellState();
}

class _SignedInShellState extends State<SignedInShell> {
  static const int _defaultTab = 1; // DAW first

  int _selectedIndex = _defaultTab;

  void _onTabTapped(int index) {
    if (index == _selectedIndex) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.isInitializing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (!auth.isSignedIn) {
      return const LoginScreen();
    }

    final capabilities = PlatformCapabilities.current;
    final tabs = <_SignedInTab>[
      const _SignedInTab(icon: Icons.music_note_rounded),
      const _SignedInTab(icon: Icons.grid_view_rounded),
      if (capabilities.supportsVideoProjects)
        const _SignedInTab(icon: Icons.video_library_rounded),
      const _SignedInTab(icon: Icons.person_rounded),
    ];
    final pages = <Widget>[
      const _HomeComingSoonScreen(),
      const ProjectsScreen(),
      if (capabilities.supportsVideoProjects) const VideoProjectsScreen(),
      const AccountScreen(showTopBar: false),
    ];

    final maxIndex = tabs.length - 1;
    final clampedSelectedIndex = _selectedIndex.clamp(0, maxIndex);
    if (clampedSelectedIndex != _selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedIndex = clampedSelectedIndex);
      });
    }

    return Scaffold(
      body: IndexedStack(
        index: clampedSelectedIndex,
        children: pages,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _BottomDock(
          selectedIndex: clampedSelectedIndex,
          tabs: tabs,
          onTap: _onTabTapped,
        ),
      ),
    );
  }
}

class _SignedInTab {
  const _SignedInTab({
    required this.icon,
  });

  final IconData icon;
}

class _BottomDock extends StatelessWidget {
  static const double _barHeight = 48;
  static const double _iconSize = 22;

  const _BottomDock({
    required this.selectedIndex,
    required this.tabs,
    required this.onTap,
  });

  final int selectedIndex;
  final List<_SignedInTab> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _barHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF0E1F3A),
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.12))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final tab = tabs[index];
          final active = index == selectedIndex;

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(index),
              child: Container(
                alignment: Alignment.center,
                height: _barHeight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab.icon,
                      size: _iconSize,
                      color: active ? Colors.white : Colors.white70,
                    ),
                    const SizedBox(height: 5),
                    if (active)
                      Container(
                        width: 18,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _HomeComingSoonScreen extends StatelessWidget {
  const _HomeComingSoonScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C1A32),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
            decoration: BoxDecoration(
              color: const Color(0xFF142845),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.music_note_rounded,
                  color: Colors.white70,
                  size: 52,
                ),
                SizedBox(height: 14),
                Text(
                  'Home',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Audio platform coming soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
