class ReleaseNote {
  const ReleaseNote({required this.version, required this.notes});

  final String version;
  final List<String> notes;
}

class ThirdPartyProgram {
  const ThirdPartyProgram({required this.name, required this.usage});

  final String name;
  final String usage;
}

/// Latest first. English only — per-build copy is not sent through l10n.
const releaseNotes = <ReleaseNote>[
  ReleaseNote(
    version: '1.0.3',
    notes: [
      'Build 1.0.3.',
    ],
  ),

  ReleaseNote(
    version: '1.0.2',
    notes: [
      'Build 1.0.2.',
    ],
  ),

  ReleaseNote(
    version: '1.0.1',
    notes: [
      'Build 1.0.1.',
    ],
  ),

  ReleaseNote(
    version: '1.0.0',
    notes: [
      'First Android client: add your own host, then chat, DM, and join voice.',
      'App lock, notifications, and optional closed-app alerts via Firebase.',
      'Share photos and files into Kurier from other apps.',
    ],
  ),
];

/// Notices the Android client must show under third-party licenses.
const thirdPartyPrograms = <ThirdPartyProgram>[
  ThirdPartyProgram(
    name: 'Twemoji (Twitter)',
    usage:
        'Emoji artwork from Twemoji (Twitter), licensed CC-BY 4.0. '
        'https://creativecommons.org/licenses/by/4.0/',
  ),
];
