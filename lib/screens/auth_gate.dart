import 'package:flutter/material.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/screens/login.dart';
import 'package:mixroom/screens/signed_in_shell.dart';
import 'package:provider/provider.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        if (auth.isInitializing) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final target = auth.isSignedIn ? const SignedInShell() : const LoginScreen();

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey(auth.isSignedIn),
            child: target,
          ),
        );
      },
    );
  }
}
