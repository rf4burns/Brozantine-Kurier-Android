import 'package:flutter/foundation.dart';

import 'app_platform.dart';

/// Session kind sent as tRPC `connectionParams.client`.
///
/// Android/iOS (app or mobile browser) is mobile. Windows/macOS/Linux
/// native (including Sharkord-native-source) and PC browsers are desktop.
String kurierClientKind() {
  if (isNativeMobile) return 'mobile';
  if (!kIsWeb) return 'desktop';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return 'mobile';
    default:
      return 'desktop';
  }
}
