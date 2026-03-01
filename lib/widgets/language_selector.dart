import 'package:flutter/material.dart';
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
          color: const Color(0xFF0F2038),
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
              color: backgroundColor ?? Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? Colors.white.withOpacity(0.16),
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
                    color: textColor.withOpacity(0.6),
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
