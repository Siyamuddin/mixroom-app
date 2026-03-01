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

  static String? validate(String password) {
    final safe = password.trim();
    if (safe.length < minLength) {
      return 'Password must be at least $minLength characters.';
    }
    if (requireUppercase && !RegExp(r'[A-Z]').hasMatch(safe)) {
      return 'Password must include an uppercase letter.';
    }
    if (requireLowercase && !RegExp(r'[a-z]').hasMatch(safe)) {
      return 'Password must include a lowercase letter.';
    }
    if (requireNumber && !RegExp(r'\d').hasMatch(safe)) {
      return 'Password must include a number.';
    }
    if (requireSymbol && !RegExp(r'[^A-Za-z0-9]').hasMatch(safe)) {
      return 'Password must include a symbol.';
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
}
