import 'package:flutter_test/flutter_test.dart';
import 'package:kurier_web/app/app_version.dart';
import 'package:kurier_web/app/release_notes.dart';

void main() {
  test('odometer wraps z then y then x', () {
    expect(AppSemVer.parse('1.0.0+1').bump().pubspec, '1.0.1+2');
    expect(AppSemVer.parse('1.0.9+9').bump().pubspec, '1.1.0+10');
    expect(AppSemVer.parse('1.9.9+20').bump().pubspec, '2.0.0+21');
    expect(AppSemVer.parse('2.0.0+21').name, '2.0.0');
  });

  test('9.9.9 overflow throws', () {
    expect(() => AppSemVer.parse('9.9.9+1').bump(), throwsStateError);
  });

  test('rejects components above 9', () {
    expect(() => AppSemVer.parse('1.0.10+1'), throwsFormatException);
  });

  test('displayAppVersion prefers package info then stamp', () {
    expect(displayAppVersion(packageVersion: '1.2.3+9'), '1.2.3');
    expect(displayAppVersion(stamp: '1.0.4'), '1.0.4');
    expect(displayAppVersion(stamp: 'dev'), '1.0.0');
    expect(displayAppVersion(), '1.0.0');
  });

  test('replacePubspecVersion rewrites the version line', () {
    const src = 'name: kurier_web\nversion: 1.0.0+1\n';
    expect(
      replacePubspecVersion(src, AppSemVer.parse('1.0.1+2')),
      'name: kurier_web\nversion: 1.0.1+2\n',
    );
    expect(parsePubspecVersion(src).name, '1.0.0');
  });

  test('insertReleaseNoteBlock prepends a version', () {
    const src = '''
const releaseNotes = <ReleaseNote>[
  ReleaseNote(
    version: '1.0.0',
    notes: [
      'First Android client.',
    ],
  ),
];
''';
    final next = insertReleaseNoteBlock(
      src,
      version: '1.0.1',
      notes: ['Fixed voice reconnect.'],
    );
    expect(
      next.indexOf("version: '1.0.1'"),
      lessThan(next.indexOf("version: '1.0.0'")),
    );
    expect(next, contains("Fixed voice reconnect."));
    expect(
      insertReleaseNoteBlock(next, version: '1.0.1', notes: ['dup']),
      next,
    );
  });

  test('1.0.0 ships with changelog and third-party programs', () {
    expect(releaseNotes.first.version, '1.0.0');
    expect(releaseNotes.first.notes, isNotEmpty);
    expect(thirdPartyPrograms, isNotEmpty);
    expect(thirdPartyPrograms.any((p) => p.name.contains('Twemoji')), isTrue);
    expect(thirdPartyPrograms.any((p) => p.name.contains('Firebase')), isTrue);
  });
}
