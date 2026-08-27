import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n_tables.dart';

const supportedLocales = [
  Locale('en'),
  Locale('cs'),
  Locale('es'),
  Locale('fr'),
  Locale('it'),
  Locale('ru'),
  Locale('zh'),
];

class L10n {
  L10n(this.locale);
  final Locale locale;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n) ?? L10n(const Locale('en'));
  }

  String t(String key, [Map<String, String>? args]) {
    final table = l10nTables[locale.languageCode] ?? l10nEn;
    var value = table[key] ?? l10nEn[key] ?? key;
    args?.forEach((k, v) {
      value = value.replaceAll('{$k}', v);
    });
    return value;
  }

  String call(String key, [Map<String, String>? args]) => t(key, args);
}

class L10nDelegate extends LocalizationsDelegate<L10n> {
  const L10nDelegate();
  @override
  bool isSupported(Locale locale) =>
      supportedLocales.any((l) => l.languageCode == locale.languageCode);
  @override
  Future<L10n> load(Locale locale) async => L10n(locale);
  @override
  bool shouldReload(covariant LocalizationsDelegate<L10n> old) => false;
}

final localeProvider = StateProvider<Locale>((ref) => const Locale('en'));
