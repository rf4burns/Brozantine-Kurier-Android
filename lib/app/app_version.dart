/// User-facing Kurier version is `x.y.z` with each component 0–9.
/// Flutter still stores `+n` in pubspec as Android `versionCode`.
class AppSemVer {
  const AppSemVer({
    required this.x,
    required this.y,
    required this.z,
    required this.build,
  });

  final int x;
  final int y;
  final int z;
  final int build;

  String get name => '$x.$y.$z';

  String get pubspec => '$name+$build';

  /// Increments patch `z`, wrapping into `y` then `x`. Always increments [build].
  AppSemVer bump() {
    if (x == 9 && y == 9 && z == 9) {
      throw StateError('version overflow: $name');
    }
    var nx = x;
    var ny = y;
    var nz = z + 1;
    if (nz > 9) {
      nz = 0;
      ny += 1;
    }
    if (ny > 9) {
      ny = 0;
      nx += 1;
    }
    return AppSemVer(x: nx, y: ny, z: nz, build: build + 1);
  }

  factory AppSemVer.parse(String raw) {
    final m = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$',
    ).firstMatch(raw.trim());
    if (m == null) {
      throw FormatException('invalid version: $raw');
    }
    final parsed = AppSemVer(
      x: int.parse(m[1]!),
      y: int.parse(m[2]!),
      z: int.parse(m[3]!),
      build: int.parse(m[4] ?? '0'),
    );
    if (parsed.x > 9 || parsed.y > 9 || parsed.z > 9) {
      throw FormatException('version digits must be 0-9: $raw');
    }
    if (parsed.build < 0) {
      throw FormatException('build must be >= 0: $raw');
    }
    return parsed;
  }
}

/// About shows `x.y.z` only. Package info wins; dart-define stamp is fallback.
String displayAppVersion({String? packageVersion, String stamp = ''}) {
  final fromPkg = (packageVersion ?? '').trim().split('+').first.trim();
  if (RegExp(r'^\d+\.\d+\.\d+$').hasMatch(fromPkg)) return fromPkg;
  final s = stamp.trim();
  if (s.isNotEmpty && s != 'dev') return s;
  return '1.0.0';
}

AppSemVer parsePubspecVersion(String pubspec) {
  final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
  if (m == null) {
    throw FormatException('pubspec.yaml has no version:');
  }
  return AppSemVer.parse(m[1]!);
}

String replacePubspecVersion(String pubspec, AppSemVer version) {
  if (!RegExp(r'^version:\s*', multiLine: true).hasMatch(pubspec)) {
    throw StateError('pubspec.yaml has no version: line');
  }
  return pubspec.replaceFirstMapped(
    RegExp(r'^version:\s*.+$', multiLine: true),
    (_) => 'version: ${version.pubspec}',
  );
}

String dartStringLiteral(String value) {
  return "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";
}

final _placeholderBuildNote = RegExp(
  r'^Build \d+\.\d+\.\d+\.?$',
  caseSensitive: false,
);

/// True when a bullet is something a client would actually want to read.
bool isClientFacingReleaseNote(String note) {
  final t = note.trim();
  return t.isNotEmpty && !_placeholderBuildNote.hasMatch(t);
}

List<String> clientFacingReleaseNotes(Iterable<String> notes) {
  return notes.map((s) => s.trim()).where(isClientFacingReleaseNote).toList();
}

/// Inserts a new [ReleaseNote] at the head of `const releaseNotes = <ReleaseNote>[`.
String insertReleaseNoteBlock(
  String source, {
  required String version,
  required List<String> notes,
}) {
  const marker = 'const releaseNotes = <ReleaseNote>[';
  final i = source.indexOf(marker);
  if (i < 0) {
    throw StateError('releaseNotes list not found');
  }
  if (source.contains("version: '$version'")) {
    return source;
  }
  final bullets = clientFacingReleaseNotes(notes);
  if (bullets.isEmpty) {
    throw ArgumentError(
      'client-facing changelog notes are required for $version',
    );
  }
  final block = StringBuffer()
    ..writeln()
    ..writeln('  ReleaseNote(')
    ..writeln('    version: ${dartStringLiteral(version)},')
    ..writeln('    notes: [');
  for (final note in bullets) {
    block.writeln('      ${dartStringLiteral(note)},');
  }
  block
    ..writeln('    ],')
    ..writeln('  ),');
  final insertAt = i + marker.length;
  return source.substring(0, insertAt) +
      block.toString() +
      source.substring(insertAt);
}
