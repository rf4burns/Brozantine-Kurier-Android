import 'package:flutter/material.dart';

import '../app/theme.dart';

Key gifFavouriteStarKey(String url) => Key('gif-star-$url');

/// Discord-style favourite star overlay used on GIF tiles and in-chat embeds.
class GifFavouriteStar extends StatelessWidget {
  const GifFavouriteStar({
    super.key,
    required this.favourited,
    required this.onPressed,
  });

  final bool favourited;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            favourited ? Icons.star : Icons.star_border,
            size: 16,
            color: favourited ? context.k.accent : Colors.white,
          ),
        ),
      ),
    );
  }
}
