import 'package:flutter/material.dart';

enum ThemePreset {
  dark,
  midnight,
  slate,
  charcoal,
  ocean,
  forest,
  dusk,
  crimson,
  light,
  sand,
  paper,
  arctic,
}

const overlayAccent = Color(0xFF5865F2);
const kurierAccent = Color(0xFF3B82F6);
const defaultAccent = overlayAccent;

const accentSwatches = [
  Color(0xFF5865F2),
  Color(0xFF3BA55D),
  Color(0xFFEB459E),
  Color(0xFFFAA61A),
  Color(0xFFED4245),
  Color(0xFF00A8FC),
  Color(0xFF9B59B6),
  Color(0xFF1ABC9C),
  Color(0xFFE67E22),
  Color(0xFF2ECC71),
  Color(0xFFF1C40F),
  Color(0xFF3498DB),
  Color(0xFFE91E63),
  Color(0xFF00BCD4),
  Color(0xFF795548),
  Color(0xFF607D8B),
];

class Palette {
  const Palette({
    required this.background,
    required this.sidebar,
    required this.rail,
    required this.card,
    required this.online,
    required this.idle,
    required this.dnd,
    required this.offline,
    required this.foreground,
    required this.muted,
    required this.faint,
    required this.divider,
  });

  final Color background;
  final Color sidebar;
  final Color rail;
  final Color card;
  final Color online;
  final Color idle;
  final Color dnd;
  final Color offline;
  final Color foreground;
  final Color muted;
  final Color faint;
  final Color divider;

  bool get isLight =>
      background.computeLuminance() > 0.5;
}

const palettes = {
  ThemePreset.dark: Palette(
    background: Color(0xFF313338),
    sidebar: Color(0xFF2B2D31),
    rail: Color(0xFF1E1F22),
    card: Color(0xFF383A40),
    online: Color(0xFF23A55A),
    idle: Color(0xFFF0B232),
    dnd: Color(0xFFF23F43),
    offline: Color(0xFF80848E),
    foreground: Color(0xFFF2F3F5),
    muted: Color(0xFFB5BAC1),
    faint: Color(0xFF949BA4),
    divider: Color(0xFF3F4147),
  ),
  ThemePreset.midnight: Palette(
    background: Color(0xFF111214),
    sidebar: Color(0xFF0B0C0E),
    rail: Color(0xFF000000),
    card: Color(0xFF1A1B1E),
    online: Color(0xFF23A55A),
    idle: Color(0xFFF0B232),
    dnd: Color(0xFFF23F43),
    offline: Color(0xFF80848E),
    foreground: Color(0xFFEDEEF0),
    muted: Color(0xFFB5BAC1),
    faint: Color(0xFF949BA4),
    divider: Color(0xFF232428),
  ),
  ThemePreset.slate: Palette(
    background: Color(0xFF2A3038),
    sidebar: Color(0xFF222830),
    rail: Color(0xFF171C22),
    card: Color(0xFF333A44),
    online: Color(0xFF23A55A),
    idle: Color(0xFFF0B232),
    dnd: Color(0xFFF23F43),
    offline: Color(0xFF80848E),
    foreground: Color(0xFFE8ECF1),
    muted: Color(0xFFA8B0BC),
    faint: Color(0xFF8A93A0),
    divider: Color(0xFF3A424D),
  ),
  ThemePreset.charcoal: Palette(
    background: Color(0xFF2C2A28),
    sidebar: Color(0xFF242220),
    rail: Color(0xFF1A1816),
    card: Color(0xFF353230),
    online: Color(0xFF23A55A),
    idle: Color(0xFFF0B232),
    dnd: Color(0xFFF23F43),
    offline: Color(0xFF80848E),
    foreground: Color(0xFFF3EFEA),
    muted: Color(0xFFB8B0A6),
    faint: Color(0xFF9A9288),
    divider: Color(0xFF403C38),
  ),
  ThemePreset.ocean: Palette(
    background: Color(0xFF1B2838),
    sidebar: Color(0xFF152232),
    rail: Color(0xFF0E1724),
    card: Color(0xFF243448),
    online: Color(0xFF23A55A),
    idle: Color(0xFFF0B232),
    dnd: Color(0xFFF23F43),
    offline: Color(0xFF80848E),
    foreground: Color(0xFFE6EEF7),
    muted: Color(0xFFA4B4C8),
    faint: Color(0xFF8494A8),
    divider: Color(0xFF2C3E52),
  ),
  ThemePreset.forest: Palette(
    background: Color(0xFF1E2A24),
    sidebar: Color(0xFF18221D),
    rail: Color(0xFF101814),
    card: Color(0xFF27352E),
    online: Color(0xFF2ECC71),
    idle: Color(0xFFF0B232),
    dnd: Color(0xFFF23F43),
    offline: Color(0xFF80848E),
    foreground: Color(0xFFE8F0EB),
    muted: Color(0xFFA8B8AE),
    faint: Color(0xFF889890),
    divider: Color(0xFF2F3F36),
  ),
  ThemePreset.dusk: Palette(
    background: Color(0xFF26242E),
    sidebar: Color(0xFF201E2C),
    rail: Color(0xFF16141F),
    card: Color(0xFF302E3C),
    online: Color(0xFF23A55A),
    idle: Color(0xFFF0B232),
    dnd: Color(0xFFF23F43),
    offline: Color(0xFF80848E),
    foreground: Color(0xFFEDEAF5),
    muted: Color(0xFFB0AAC0),
    faint: Color(0xFF908AA0),
    divider: Color(0xFF3A3748),
  ),
  ThemePreset.crimson: Palette(
    background: Color(0xFF2E2224),
    sidebar: Color(0xFF261C1E),
    rail: Color(0xFF1A1214),
    card: Color(0xFF3A2A2C),
    online: Color(0xFF23A55A),
    idle: Color(0xFFF0B232),
    dnd: Color(0xFFF23F43),
    offline: Color(0xFF80848E),
    foreground: Color(0xFFF5EAEA),
    muted: Color(0xFFC0A8A8),
    faint: Color(0xFFA08888),
    divider: Color(0xFF443436),
  ),
  ThemePreset.light: Palette(
    background: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF2F3F5),
    rail: Color(0xFFE3E5E8),
    card: Color(0xFFEBEDEF),
    online: Color(0xFF248A45),
    idle: Color(0xFFB8860B),
    dnd: Color(0xFFD83C3E),
    offline: Color(0xFF80848E),
    foreground: Color(0xFF060607),
    muted: Color(0xFF4E5058),
    faint: Color(0xFF5C5E66),
    divider: Color(0xFFD7D9DC),
  ),
  ThemePreset.sand: Palette(
    background: Color(0xFFF7F1E8),
    sidebar: Color(0xFFEDE4D6),
    rail: Color(0xFFE0D4C2),
    card: Color(0xFFE8DDCF),
    online: Color(0xFF248A45),
    idle: Color(0xFFB8860B),
    dnd: Color(0xFFD83C3E),
    offline: Color(0xFF80848E),
    foreground: Color(0xFF2A241C),
    muted: Color(0xFF5C5348),
    faint: Color(0xFF6E6458),
    divider: Color(0xFFD4C8B6),
  ),
  ThemePreset.paper: Palette(
    background: Color(0xFFFAFAF8),
    sidebar: Color(0xFFF0F0EC),
    rail: Color(0xFFE4E4DE),
    card: Color(0xFFECECE6),
    online: Color(0xFF248A45),
    idle: Color(0xFFB8860B),
    dnd: Color(0xFFD83C3E),
    offline: Color(0xFF80848E),
    foreground: Color(0xFF1A1A18),
    muted: Color(0xFF555550),
    faint: Color(0xFF6A6A64),
    divider: Color(0xFFD8D8D0),
  ),
  ThemePreset.arctic: Palette(
    background: Color(0xFFF2F6FA),
    sidebar: Color(0xFFE6EEF5),
    rail: Color(0xFFD5E0EB),
    card: Color(0xFFDDE7F0),
    online: Color(0xFF248A45),
    idle: Color(0xFFB8860B),
    dnd: Color(0xFFD83C3E),
    offline: Color(0xFF80848E),
    foreground: Color(0xFF121820),
    muted: Color(0xFF4A5868),
    faint: Color(0xFF5C6A7A),
    divider: Color(0xFFC8D4E0),
  ),
};

class KurierColors extends ThemeExtension<KurierColors> {
  const KurierColors({
    required this.palette,
    required this.accent,
  });

  final Palette palette;
  final Color accent;

  @override
  KurierColors copyWith({Palette? palette, Color? accent}) {
    return KurierColors(
      palette: palette ?? this.palette,
      accent: accent ?? this.accent,
    );
  }

  @override
  KurierColors lerp(ThemeExtension<KurierColors>? other, double t) {
    if (other is! KurierColors) return this;
    return KurierColors(
      palette: t < 0.5 ? palette : other.palette,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
    );
  }
}

ThemeData buildTheme(ThemePreset preset, Color accent) {
  final p = palettes[preset]!;
  final scheme = p.isLight ? Brightness.light : Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: scheme,
    colorScheme: ColorScheme(
      brightness: scheme,
      primary: accent,
      onPrimary: Colors.white,
      secondary: p.card,
      onSecondary: p.foreground,
      error: p.dnd,
      onError: Colors.white,
      surface: p.background,
      onSurface: p.foreground,
    ),
    scaffoldBackgroundColor: p.background,
    dividerColor: p.divider,
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(32, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.all(4),
        iconSize: 18,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: p.divider),
      ),
      titleTextStyle: TextStyle(
        color: p.foreground,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(color: p.muted, fontSize: 14, height: 1.4),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return accent;
        return p.rail;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    extensions: [KurierColors(palette: p, accent: accent)],
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: p.foreground, fontSize: 15, height: 1.35),
      bodySmall: TextStyle(color: p.muted, fontSize: 13),
      titleMedium: TextStyle(
        color: p.foreground,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    ),
  );
}

extension ThemeX on BuildContext {
  KurierColors get k => Theme.of(this).extension<KurierColors>()!;
  Palette get p => k.palette;
}
