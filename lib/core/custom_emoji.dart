/// Server custom emoji for the picker, glyphs, and codec (name + image URL).
class CustomEmoji {
  const CustomEmoji({required this.name, this.url});

  final String name;
  final String? url;
}
