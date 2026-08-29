const presenceOnline = 'online';
const presenceIdle = 'idle';

const presenceFocusAwayDebounce = Duration(seconds: 2);

/// Public presence this session should report.
///
/// Voice always wins. Manual Away sticks while focused. Otherwise unfocused
/// sessions report idle.
String intendedPresenceStatus({
  required bool manualAway,
  required bool focused,
  required bool inVoice,
}) {
  if (inVoice) return presenceOnline;
  if (manualAway) return presenceIdle;
  return focused ? presenceOnline : presenceIdle;
}

String presenceLabelKey(String? status) {
  switch (status) {
    case presenceIdle:
      return 'statusAway';
    case presenceOnline:
    case 'dnd':
      return 'statusOnline';
    default:
      return 'statusOffline';
  }
}
