import 'package:flutter/widgets.dart';

Widget mediaStreamView({required String mediaKey, BoxFit fit = BoxFit.cover}) {
  return SizedBox.expand(key: ValueKey('media-$mediaKey-$fit'));
}
