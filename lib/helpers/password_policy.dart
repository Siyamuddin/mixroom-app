import 'package:flutter/material.dart';
import 'package:mixroom/l10n/l10n.dart';

class PasswordPolicy {
  const PasswordPolicy._();

  static const int minLength = int.fromEnvironment(
    'COGNITO_PASSWORD_MIN_LENGTH',
    defaultValue: 8,
  );

  static const bool requireUppercase = bool.fromEnvironment(
    'COGNITO_PASSWORD_REQUIRE_UPPERCASE',
    defaultValue: true,
  );

  static const bool requireLowercase = bool.fromEnvironment(
    'COGNITO_PASSWORD_REQUIRE_LOWERCASE',
    defaultValue: true,
  );

  static const bool requireNumber = bool.fromEnvironment(
    'COGNITO_PASSWORD_REQUIRE_NUMBER',
    defaultValue: true,
  );

  static const bool requireSymbol = bool.fromEnvironment(
    'COGNITO_PASSWORD_REQUIRE_SYMBOL',
    defaultValue: true,
  );

  static List<String> validateIssues(String password) {
    final safe = password.trim();
    final issues = <String>[];
    if (safe.length < minLength) {
      issues.add('Password must be at least $minLength characters.');
    }
    if (requireUppercase && !RegExp(r'[A-Z]').hasMatch(safe)) {
      issues.add('Password must include an uppercase letter.');
    }
    if (requireLowercase && !RegExp(r'[a-z]').hasMatch(safe)) {
      issues.add('Password must include a lowercase letter.');
    }
    if (requireNumber && !RegExp(r'\d').hasMatch(safe)) {
      issues.add('Password must include a number.');
    }
    if (requireSymbol && !RegExp(r'[^A-Za-z0-9]').hasMatch(safe)) {
      issues.add('Password must include a symbol.');
    }
    return issues;
  }

  static String? validate(String password) {
    final issues = validateIssues(password);
    if (issues.isEmpty) return null;
    return issues.first;
  }

  static String? validateLocalized(BuildContext context, String password) {
    final safe = password.trim();
    String requirementText(String key) {
      return L10n.translate(
        context,
        'Use {requirements}.',
      ).replaceAll('{requirements}', L10n.translate(context, key));
    }

    if (safe.length < minLength) {
      final lengthText = L10n.translate(
        context,
        'at least {minLength} characters',
      ).replaceAll('{minLength}', '$minLength');
      return L10n.translate(
        context,
        'Use {requirements}.',
      ).replaceAll('{requirements}', lengthText);
    }
    if (requireUppercase && !RegExp(r'[A-Z]').hasMatch(safe)) {
      return requirementText('an uppercase letter');
    }
    if (requireLowercase && !RegExp(r'[a-z]').hasMatch(safe)) {
      return requirementText('a lowercase letter');
    }
    if (requireNumber && !RegExp(r'\d').hasMatch(safe)) {
      return requirementText('a number');
    }
    if (requireSymbol && !RegExp(r'[^A-Za-z0-9]').hasMatch(safe)) {
      return requirementText('a symbol');
    }
    return null;
  }

  static String requirementsText() {
    final parts = <String>['at least $minLength characters'];
    if (requireUppercase) parts.add('an uppercase letter');
    if (requireLowercase) parts.add('a lowercase letter');
    if (requireNumber) parts.add('a number');
    if (requireSymbol) parts.add('a symbol');
    return 'Use ${parts.join(', ')}.';
  }

  static String requirementsTextLocalized(BuildContext context) {
    final parts = <String>[
      L10n.translate(
        context,
        'at least {minLength} characters',
      ).replaceAll('{minLength}', '$minLength'),
    ];
    if (requireUppercase) {
      parts.add(L10n.translate(context, 'an uppercase letter'));
    }
    if (requireLowercase) {
      parts.add(L10n.translate(context, 'a lowercase letter'));
    }
    if (requireNumber) {
      parts.add(L10n.translate(context, 'a number'));
    }
    if (requireSymbol) {
      parts.add(L10n.translate(context, 'a symbol'));
    }
    return L10n.translate(
      context,
      'Use {requirements}.',
    ).replaceAll('{requirements}', parts.join(', '));
  }
}
