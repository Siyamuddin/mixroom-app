import 'package:flutter/material.dart';
import 'package:mixroom/helpers/glass_ui_tokens.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/providers/locale_provider.dart';
import 'package:provider/provider.dart';

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.backgroundColor,
    this.borderColor,
    this.textColor = Colors.white,
    this.borderRadius = 10,
    this.fontSize = 12,
  });

  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color textColor;
  final double borderRadius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        final locale = L10n.resolveSupportedLocale(localeProvider.locale);
        final code = locale.languageCode.toUpperCase();
        final flag = L10n.languageFlag(locale);

        return PopupMenuButton<Locale>(
          tooltip: L10n.translate(context, 'Language'),
          onSelected: (selectedLocale) =>
              L10n.setLocale(context, selectedLocale),
          color: kMixroomGlassDropdownMenuColor,
          surfaceTintColor: Colors.transparent,
          shadowColor: const Color.fromRGBO(0, 0, 0, 0.22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: borderColor ?? Colors.white.withValues(alpha: 0.16),
            ),
          ),
          itemBuilder: (context) {
            return L10n.supportedLocales.map((supportedLocale) {
              final itemCode = supportedLocale.languageCode.toUpperCase();
              final itemFlag = L10n.languageFlag(supportedLocale);
              final itemName = L10n.languageName(supportedLocale);
              return PopupMenuItem<Locale>(
                value: supportedLocale,
                child: Row(
                  children: [
                    Text(itemFlag, style: const TextStyle(fontSize: 17)),
                    const SizedBox(width: 8),
                    Text(
                      '$itemCode  $itemName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: backgroundColor ?? Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? Colors.white.withValues(alpha: 0.16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(flag, style: TextStyle(fontSize: fontSize + 4)),
                const SizedBox(width: 6),
                Text(
                  '|',
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.6),
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  code,
                  style: TextStyle(
                    color: textColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
