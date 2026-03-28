import 'package:flutter/material.dart';
import 'package:mixroom/helpers/auth_service.dart';
import 'package:mixroom/helpers/native_social_sign_in.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/models/auth_user_profile.dart';
import 'package:mixroom/widgets/app_shell_figma.dart';

Future<bool?> showDeleteAccountSheet(
  BuildContext context, {
  required AuthService auth,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (_) => DeleteAccountSheet(auth: auth),
  );
}

class DeleteAccountSheet extends StatefulWidget {
  const DeleteAccountSheet({
    super.key,
    required this.auth,
  });

  final AuthService auth;

  @override
  State<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<DeleteAccountSheet> {
  final TextEditingController _confirmationController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  NativeSocialSignInPayload? _socialReauthPayload;
  String? _inlineError;
  bool _hidePassword = true;
  bool _isReauthenticating = false;

  AuthUserProfile? get _user => widget.auth.currentUser;
  bool get _usesEmailPassword => _user?.provider == AuthProviderType.email;
  bool get _deleteConfirmed =>
      _confirmationController.text.trim().toUpperCase() == 'DELETE';

  @override
  void dispose() {
    _confirmationController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = _user;
    if (user == null) {
      setState(() => _inlineError = 'No active account.');
      return;
    }
    if (!_deleteConfirmed) {
      setState(() {
        _inlineError = 'Type DELETE to confirm account deletion.';
      });
      return;
    }
    if (_usesEmailPassword && _passwordController.text.isEmpty) {
      setState(() {
        _inlineError = 'Enter your current password to delete this account.';
      });
      return;
    }
    if (!_usesEmailPassword && _socialReauthPayload == null) {
      setState(() {
        _inlineError =
            'Re-authenticate with ${user.provider.label} to delete this account.';
      });
      return;
    }

    setState(() => _inlineError = null);
    try {
      await widget.auth.deleteAccount(
        confirmationText: _confirmationController.text.trim(),
        currentPassword: _usesEmailPassword ? _passwordController.text : null,
        socialReauth: _socialReauthPayload,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineError = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _reauthenticateSocial() async {
    setState(() {
      _inlineError = null;
      _isReauthenticating = true;
    });
    try {
      final payload = await widget.auth.beginDeleteAccountSocialReauth();
      if (!mounted) return;
      setState(() {
        _socialReauthPayload = payload;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineError = e.toString().replaceFirst('Bad state: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isReauthenticating = false);
      }
    }
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String label,
    required String hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: L10n.translate(context, label),
      hintText: L10n.translate(context, hint),
      labelStyle: TextStyle(
        fontFamily: 'Pretendard',
        color: Colors.white.withValues(alpha: 0.84),
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        fontFamily: 'Pretendard',
        color: Colors.white.withValues(alpha: 0.34),
        fontSize: 13,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: Color(0xFF76B3FF), width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFF8A94), width: 1.1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFF8A94), width: 1.3),
      ),
    );
  }

  Widget _buildWarningItem(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 15, color: const Color(0xFFF4F4F4)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            L10n.translate(context, text),
            style: TextStyle(
              fontFamily: 'Pretendard',
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: widget.auth,
      builder: (context, _) {
        final busy = widget.auth.isBusy;
        final insets = MediaQuery.of(context).viewInsets;
        final canDelete = !busy &&
            !_isReauthenticating &&
            _deleteConfirmed &&
            (_usesEmailPassword
                ? _passwordController.text.isNotEmpty
                : _socialReauthPayload != null);

        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: MixroomShellSurface(
                radius: 30,
                strong: true,
                color: const Color.fromRGBO(20, 28, 40, 0.96),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.30),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color.fromRGBO(184, 74, 74, 0.24),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.delete_forever_rounded,
                              color: Color(0xFFF7D0D0),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  L10n.translate(context, 'Delete account'),
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Color(0xFFF4F4F4),
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  L10n.translate(
                                    context,
                                    'This permanently removes your Mixroom account and signed-in session on this device.',
                                  ),
                                  style: TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      MixroomShellSurface(
                        radius: 24,
                        color: const Color.fromRGBO(184, 74, 74, 0.16),
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  L10n.translate(
                                      context, 'Before you continue'),
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Color(0xFFF4F4F4),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  user.provider.label,
                                  style: TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Colors.white.withValues(alpha: 0.62),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _buildWarningItem(
                              Icons.warning_amber_rounded,
                              'Your profile, auth access, and linked account data will be removed.',
                            ),
                            const SizedBox(height: 10),
                            _buildWarningItem(
                              Icons.credit_card_rounded,
                              'Deleting your Mixroom account does not cancel App Store or Google Play billing. Cancel there first if needed.',
                            ),
                            const SizedBox(height: 10),
                            _buildWarningItem(
                              Icons.lock_reset_rounded,
                              'To protect your account, Mixroom will ask you to confirm DELETE and verify this session one more time.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      MixroomShellSurface(
                        radius: 22,
                        color: const Color.fromRGBO(244, 244, 244, 0.08),
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                user.initials,
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: Color(0xFFF4F4F4),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.email,
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      color: Color(0xFFF4F4F4),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    L10n.translate(
                                      context,
                                      'Signed in with ${user.provider.label}',
                                    ),
                                    style: TextStyle(
                                      fontFamily: 'Pretendard',
                                      color:
                                          Colors.white.withValues(alpha: 0.62),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _confirmationController,
                        textCapitalization: TextCapitalization.characters,
                        autocorrect: false,
                        onChanged: (_) => setState(() => _inlineError = null),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: Color(0xFFF4F4F4),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: _inputDecoration(
                          context,
                          label: 'Type DELETE to continue',
                          hint: 'DELETE',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_usesEmailPassword)
                        TextField(
                          controller: _passwordController,
                          obscureText: _hidePassword,
                          autocorrect: false,
                          onChanged: (_) => setState(() => _inlineError = null),
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: Color(0xFFF4F4F4),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: _inputDecoration(
                            context,
                            label: 'Current password',
                            hint: 'Enter your password',
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() => _hidePassword = !_hidePassword);
                              },
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                          ),
                        )
                      else
                        MixroomShellSurface(
                          radius: 22,
                          color: const Color.fromRGBO(244, 244, 244, 0.08),
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      L10n.translate(
                                        context,
                                        'Confirm with ${user.provider.label}',
                                      ),
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        color: Color(0xFFF4F4F4),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (_socialReauthPayload != null)
                                    Text(
                                      L10n.translate(context, 'Verified'),
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        color: Color(0xFF9BDFBE),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                L10n.translate(
                                  context,
                                  'Run one more ${user.provider.label} sign-in check before Mixroom deletes this account.',
                                ),
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: Colors.white.withValues(alpha: 0.70),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: busy || _isReauthenticating
                                    ? null
                                    : _reauthenticateSocial,
                                child: Opacity(
                                  opacity:
                                      busy || _isReauthenticating ? 0.58 : 1,
                                  child: MixroomShellSurface(
                                    radius: 20,
                                    color: const Color.fromRGBO(
                                      244,
                                      244,
                                      244,
                                      0.12,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (_isReauthenticating) ...[
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFFF4F4F4),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                        ],
                                        Text(
                                          _socialReauthPayload == null
                                              ? L10n.translate(
                                                  context,
                                                  'Re-auth with ${user.provider.label}',
                                                )
                                              : L10n.translate(
                                                  context,
                                                  'Re-auth completed',
                                                ),
                                          style: const TextStyle(
                                            fontFamily: 'Pretendard',
                                            color: Color(0xFFF4F4F4),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if ((_inlineError ?? '').isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          _inlineError!,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: Color(0xFFFF98A0),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: busy || _isReauthenticating
                                  ? null
                                  : () => Navigator.of(context).pop(false),
                              child: Opacity(
                                opacity: busy || _isReauthenticating ? 0.58 : 1,
                                child: const MixroomShellSurface(
                                  radius: 22,
                                  color: Color.fromRGBO(244, 244, 244, 0.12),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 13,
                                  ),
                                  child: Text(
                                    'Cancel',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Pretendard',
                                      color: Color(0xFFF4F4F4),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: canDelete ? _submit : null,
                              child: Opacity(
                                opacity: canDelete ? 1 : 0.48,
                                child: MixroomShellSurface(
                                  radius: 22,
                                  color: const Color.fromRGBO(
                                    184,
                                    74,
                                    74,
                                    0.56,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 13,
                                  ),
                                  child: busy
                                      ? const SizedBox(
                                          height: 18,
                                          child: Center(
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: Color(0xFFF4F4F4),
                                              ),
                                            ),
                                          ),
                                        )
                                      : const Text(
                                          'Delete Account',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontFamily: 'Pretendard',
                                            color: Color(0xFFF4F4F4),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
