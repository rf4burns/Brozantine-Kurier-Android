import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'native/android_runtime.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAndroidRuntime();
  runApp(const ProviderScope(child: KurierApp()));
}
