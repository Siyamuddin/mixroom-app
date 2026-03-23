import 'package:flutter/material.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/l10n/l10n.dart';

Future<void> showEmailVerificationSheet(
  BuildContext context, {
  required AuthService auth,
  String? initialEmail,
  String? initialPassword,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      return EmailVerificationSheet(
        auth: auth,
        initialEmail: (initialEmail ?? auth.currentUser?.email ?? '')
            .trim()
            .toLowerCase(),
        initialPassword: initialPassword ?? '',
      );
    },
  );
}

class EmailVerificationSheet extends StatefulWidget {
  const EmailVerificationSheet({
    super.key,
    required this.auth,
    required this.initialEmail,
    required this.initialPassword,
  });

  final AuthService auth;
  final String initialEmail;
  final String initialPassword;

  @override
  State<EmailVerificationSheet> createState() => _EmailVerificationSheetState();
}

class _EmailVerificationSheetState extends State<EmailVerificationSheet> {
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  late final TextEditingController _emailController;
  final TextEditingController _codeController = TextEditingController();
  late final TextEditingController _passwordController;

  String? _inlineError;
  bool _hidePassword = true;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
    _passwordController = TextEditingController(text: widget.initialPassword);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _needsPasswordForSessionUpgrade =>
      !widget.auth.hasActiveSessionTokens;

  Future<void> _confirm() async {
    final email = _emailController.text.trim().toLowerCase();
    final code = _codeController.text.trim();
    final password = _passwordController.text;

    if (!_emailPattern.hasMatch(email)) {
      setState(() => _inlineError = 'Enter a valid email address.');
      return;
    }
    if (code.isEmpty) {
      setState(() => _inlineError = 'Enter the verification code.');
      return;
    }
    if (_needsPasswordForSessionUpgrade && password.trim().isEmpty) {
      setState(() {
        _inlineError =
            'Enter your password so Mixroom can finish signing you in after verification.';
      });
      return;
    }

    setState(() => _inlineError = null);

    try {
      await widget.auth.confirmEmailSignUp(
        email: email,
        code: code,
        passwordToSignIn: password,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.translate(context, 'Email verified. Your account is ready.'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineError = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _resendCode() async {
    final email = _emailController.text.trim().toLowerCase();
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _inlineError = 'Enter a valid email address.');
      return;
    }

    setState(() => _inlineError = null);

    try {
      final currentUserEmail =
          widget.auth.currentUser?.email.trim().toLowerCase() ?? '';
      if (currentUserEmail == email) {
        await widget.auth.resendEmailVerification();
      } else {
        await widget.auth.resendSignUpCode(email: email);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.translate(context, 'Verification code resent.')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineError = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  InputDecoration _decoration(BuildContext context, String label, String hint) {
    return InputDecoration(
      labelText: L10n.translate(context, label),
      hintText: L10n.translate(context, hint),
      labelStyle: TextStyle(
        color: Colors.white.withOpacity(0.86),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: Colors.white.withOpacity(0.40),
        fontSize: 13,
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.11)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFF5F96FF), width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF7E88), width: 1.1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF7E88), width: 1.3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.auth,
      builder: (context, _) {
        final busy = widget.auth.isBusy;
        final insets = MediaQuery.of(context).viewInsets;

        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F2038),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.30),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    L10n.translate(context, 'Verify your email'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _needsPasswordForSessionUpgrade
                        ? L10n.translate(
                            context,
                            'Enter the code from your email and your password to finish signing in.',
                          )
                        : L10n.translate(
                            context,
                            'Enter the verification code sent to your email.',
                          ),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration:
                        _decoration(context, 'Email', 'you@example.com'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _codeController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: _decoration(
                      context,
                      'Verification Code',
                      'Enter code',
                    ),
                  ),
                  if (_needsPasswordForSessionUpgrade) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordController,
                      obscureText: _hidePassword,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: _decoration(
                        context,
                        'Password',
                        'Enter your password',
                      ).copyWith(
                        suffixIcon: IconButton(
                          onPressed: busy
                              ? null
                              : () => setState(
                                    () => _hidePassword = !_hidePassword,
                                  ),
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy ? null : _resendCode,
                      child: Text(L10n.translate(context, 'Resend code')),
                    ),
                  ),
                  if (_inlineError != null) ...[
                    const SizedBox(height: 2),
                    _SheetInlineError(message: _inlineError!),
                    const SizedBox(height: 10),
                  ] else
                    const SizedBox(height: 6),
                  _SheetPrimaryButton(
                    label: busy ? 'Verifying...' : 'Verify Email',
                    busy: busy,
                    onTap: busy ? null : _confirm,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : () => Navigator.of(context).pop(),
                    child: Text(L10n.translate(context, 'Cancel')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SheetPrimaryButton extends StatelessWidget {
  const _SheetPrimaryButton({
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          gradient: const LinearGradient(
            colors: [Color(0xFF3D7FFF), Color(0xFF49CFC9)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3D7FFF).withOpacity(0.30),
              blurRadius: 16,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(13),
            onTap: onTap,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      L10n.translate(context, label),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetInlineError extends StatelessWidget {
  const _SheetInlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6E78).withOpacity(0.14),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFFF8D96).withOpacity(0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1.5),
            child: Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: Color(0xFFFFAFB5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              L10n.translate(context, message),
              style: const TextStyle(
                color: Color(0xFFFFD7DA),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
