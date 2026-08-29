import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'native/android_runtime.dart';
import 'protocol/platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAndroidRuntime();
  await PlatformBridge.refreshNotificationPermission();
  runApp(const ProviderScope(child: KurierApp()));
}
