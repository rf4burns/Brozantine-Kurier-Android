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
    version: '1.0.6',
    notes: [
      'YouTube videos play in chat again.',
      'Profiles close with back, Escape, or a tap outside the card.',
      'Profile cards fit better on phones.',
    ],
  ),

  ReleaseNote(
    version: '1.0.5',
    notes: [
      'The channel notification menu now ticks the setting this channel is using.',
    ],
  ),

  ReleaseNote(
    version: '1.0.4',
    notes: [
      'Mark as read on Android notifications works when Kurier is closed.',
    ],
  ),

  ReleaseNote(
    version: '1.0.3',
    notes: [
      'The connected-to-server notification can leave the host. Voice Disconnect still only leaves the call.',
    ],
  ),

  ReleaseNote(
    version: '1.0.2',
    notes: [
      'Switch between Online and Away from the client.',
      'Kurier goes Away in the background and stays Online while you are in voice.',
      'Mark grouped notifications as read from the notification itself.',
    ],
  ),

  ReleaseNote(
    version: '1.0.1',
    notes: [
      'Stays connected in the background when you leave the app.',
      'Groups closed-app alerts into messages, mentions, DMs, and replies.',
      'Reconnects when you return to the app, and uses the host GIF search key automatically.',
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
