import 'dart:io';

import 'package:kurier_web/app/app_version.dart';

/// Updates pubspec `x.y.z+n` and prepends a changelog block.
///
/// Prints the user-facing `x.y.z` on stdout (last line) for build scripts.
void main(List<String> args) {
  var noBump = false;
  var notes = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--no-bump') {
      noBump = true;
    } else if (arg == '--notes') {
      if (i + 1 >= args.length) {
        stderr.writeln('--notes requires a value');
        exit(64);
      }
      notes = args[++i]
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      stderr.writeln('unknown argument: $arg');
      exit(64);
    }
  }

  final pubspecFile = File('pubspec.yaml');
  final notesFile = File('lib/app/release_notes.dart');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('pubspec.yaml not found; run from the repo root');
    exit(1);
  }

  final current = parsePubspecVersion(pubspecFile.readAsStringSync());
  if (noBump) {
    stderr.writeln('Using ${current.pubspec} (no bump)');
    stdout.writeln(current.name);
    return;
  }

  final next = current.bump();
  pubspecFile.writeAsStringSync(
    replacePubspecVersion(pubspecFile.readAsStringSync(), next),
  );
  stderr.writeln('Bumped ${current.pubspec} → ${next.pubspec}');

  if (notesFile.existsSync()) {
    notesFile.writeAsStringSync(
      insertReleaseNoteBlock(
        notesFile.readAsStringSync(),
        version: next.name,
        notes: notes,
      ),
    );
  } else {
    stderr.writeln('warning: ${notesFile.path} missing; skipped changelog');
  }

  stdout.writeln(next.name);
}
