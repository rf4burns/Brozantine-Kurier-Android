import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/breakpoints.dart';
import '../app/theme.dart';
import '../core/custom_emoji.dart';
import '../core/emoji_catalog.dart';
import '../core/emoji_codec.dart';
import '../core/emoji_recent.dart';
import '../protocol/permissions.dart';
import '../session/session_controller.dart';
import 'emoji_glyph.dart';

/// Result of [showKurierEmojiPicker]: unicode or custom name, plus custom flag.
typedef EmojiPick = ({String value, bool isCustom});

Future<EmojiPick?> showKurierEmojiPicker(
  BuildContext context, {
  required SessionController session,
}) {
  final phone =
      breakpointOf(MediaQuery.sizeOf(context).width) == Breakpoint.phone;

  Widget picker() => EmojiPicker(
        session: session,
        customEmojis: session.customEmojis,
        onSelect: (value, isCustom) {
          Navigator.of(context).pop<EmojiPick>((
            value: value,
            isCustom: isCustom,
          ));
        },
      );

  if (phone) {
    return showModalBottomSheet<EmojiPick>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(ctx).bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: picker(),
        ),
      ),
    );
  }

  return showDialog<EmojiPick>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: picker(),
    ),
  );
}

/// Discord-style emoji picker: search, Emoji/Custom tabs, category rail, and
/// recently used at the top.
class EmojiPicker extends StatefulWidget {
  const EmojiPicker({
    super.key,
    required this.session,
    required this.customEmojis,
    required this.onSelect,
  });

  final SessionController session;
  final List<CustomEmoji> customEmojis;
  final void Function(String value, bool isCustom) onSelect;

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  static const _gridColumns = 9;
  static const _cellSize = 36.0;

  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _sectionKeys = <String, GlobalKey>{};

  int _tab = 0; // 0 = emoji, 1 = custom
  String? _activeCategory;
  String _query = '';
  bool _uploading = false;
  List<String> _recent = [];

  @override
  void initState() {
    super.initState();
    _recent = EmojiRecent.load();
    _search.addListener(() {
      setState(() {
        _query = _search.text.trim().toLowerCase();
        if (_query.isNotEmpty) _activeCategory = null;
      });
    });
    for (final c in EmojiCatalog.categories) {
      _sectionKeys[c.id] = GlobalKey();
    }
    _sectionKeys['recent'] = GlobalKey();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pick(String value, bool isCustom) async {
    await EmojiRecent.record(value, isCustom: isCustom);
    widget.onSelect(value, isCustom);
  }

  bool _matchesUnicode(String emoji) {
    if (_query.isEmpty) return true;
    if (emoji.toLowerCase().contains(_query)) return true;
    final sc = EmojiCodec.shortcodeForUnicode(emoji);
    if (sc != null && sc.contains(_query)) return true;
    return false;
  }

  bool _matchesCustom(CustomEmoji e) {
    if (_query.isEmpty) return true;
    return e.name.toLowerCase().contains(_query);
  }

  List<String> _filteredRecent(List<CustomEmoji> customEmojis) {
    final out = <String>[];
    for (final key in _recent) {
      if (EmojiRecent.isCustomKey(key)) {
        final name = EmojiRecent.customNameFromKey(key);
        final emoji = customEmojis.cast<CustomEmoji?>().firstWhere(
              (e) => e?.name == name,
              orElse: () => null,
            );
        if (emoji != null && _matchesCustom(emoji)) out.add(key);
      } else if (_matchesUnicode(key)) {
        out.add(key);
      }
    }
    return out;
  }

  List<EmojiCategory> get _filteredCategories {
    if (_query.isEmpty && _activeCategory != null) {
      return EmojiCatalog.categories
          .where((c) => c.id == _activeCategory)
          .toList();
    }
    if (_query.isEmpty) return EmojiCatalog.categories;
    return EmojiCatalog.categories
        .map((c) {
          final emojis = c.emojis.where(_matchesUnicode).toList();
          if (emojis.isEmpty) return null;
          return EmojiCategory(id: c.id, label: c.label, emojis: emojis);
        })
        .whereType<EmojiCategory>()
        .toList();
  }

  List<CustomEmoji> _filteredCustom(List<CustomEmoji> customEmojis) =>
      customEmojis.where(_matchesCustom).toList();

  void _scrollToCategory(String id) {
    setState(() {
      _activeCategory = id;
      _query = '';
      _search.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _sectionKeys[id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: 0,
        );
      }
    });
  }

  void _showAllCategories() {
    setState(() => _activeCategory = null);
    _scroll.jumpTo(0);
  }

  Future<void> _upload() async {
    final s = widget.session;
    if (!s.can(Permission.manageEmojis)) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _uploading = true);
    try {
      var added = 0;
      for (final f in result.files) {
        final bytes = f.bytes;
        if (bytes == null) continue;
        var name = (f.name.split('.').first)
            .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
        if (name.isEmpty) name = 'emoji';
        if (name.length > 32) name = name.substring(0, 32);
        final id = await s.uploadBytes(f.name, Uint8List.fromList(bytes));
        if (id == null) continue;
        await s.addEmoji(name, id);
        added++;
      }
      if (!mounted) return;
      if (added == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No images could be uploaded')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added $added custom emoji${added == 1 ? '' : 's'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final canUpload = widget.session.can(Permission.manageEmojis);
        final customEmojis = widget.session.customEmojis.isNotEmpty
            ? widget.session.customEmojis
            : widget.customEmojis;
        return Container(
          width: 352,
          height: 420,
          decoration: BoxDecoration(
            color: p.sidebar,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                child: TextField(
                  controller: _search,
                  style: TextStyle(color: p.foreground, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search all emojis…',
                    hintStyle: TextStyle(color: p.faint, fontSize: 13),
                    filled: true,
                    fillColor: p.rail,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: p.divider),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: p.divider),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: context.k.accent),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    _TabChip(
                      label: 'Emoji',
                      selected: _tab == 0,
                      onTap: () => setState(() => _tab = 0),
                    ),
                    const SizedBox(width: 8),
                    _TabChip(
                      label: 'Custom',
                      selected: _tab == 1,
                      onTap: () => setState(() => _tab = 1),
                    ),
                  ],
                ),
              ),
              if (_tab == 0) ...[
                const SizedBox(height: 6),
                _CategoryRail(
                  activeId: _activeCategory,
                  onPick: (id) {
                    if (_activeCategory == id) {
                      _showAllCategories();
                    } else {
                      _scrollToCategory(id);
                    }
                  },
                ),
                Expanded(child: _buildEmojiBody(customEmojis)),
              ] else
                Expanded(child: _buildCustomBody(customEmojis, canUpload)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmojiBody(List<CustomEmoji> customEmojis) {
    final recent = _filteredRecent(customEmojis);
    final categories = _filteredCategories;

    if (_query.isNotEmpty && recent.isEmpty && categories.isEmpty) {
      return Center(
        child: Text(
          'No emojis found',
          style: TextStyle(color: context.p.faint),
        ),
      );
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      children: [
        if (recent.isNotEmpty && _activeCategory == null) ...[
          _SectionHeader(
            key: _sectionKeys['recent'],
            label: 'Frequently Used',
          ),
          _EmojiGrid(
            children: recent.map((key) {
              if (EmojiRecent.isCustomKey(key)) {
                final name = EmojiRecent.customNameFromKey(key);
                final emoji = customEmojis.cast<CustomEmoji?>().firstWhere(
                      (e) => e?.name == name,
                      orElse: () => null,
                    );
                if (emoji == null) return const SizedBox.shrink();
                return _EmojiButton(
                  tooltip: ':${emoji.name}:',
                  onTap: () => _pick(emoji.name, true),
                  child: CustomEmojiGlyph(emoji: emoji, size: 26),
                );
              }
              return _EmojiButton(
                tooltip: key,
                onTap: () => _pick(key, false),
                child: NativeEmojiGlyph(unicode: key, size: 26),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
        for (final cat in categories) ...[
          _SectionHeader(
            key: _sectionKeys[cat.id],
            label: cat.label,
          ),
          _EmojiGrid(
            children: cat.emojis.map((e) {
              return _EmojiButton(
                tooltip: e,
                onTap: () => _pick(e, false),
                child: NativeEmojiGlyph(unicode: e, size: 26),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildCustomBody(List<CustomEmoji> customEmojis, bool canUpload) {
    final filtered = _filteredCustom(customEmojis);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canUpload)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : _upload,
              icon: _uploading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload, size: 16),
              label: Text(_uploading ? 'Uploading…' : 'Upload custom emoji'),
            ),
          ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _query.isNotEmpty
                        ? 'No custom emoji found'
                        : 'No server emoji yet',
                    style: TextStyle(color: context.p.faint),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _gridColumns,
                    mainAxisExtent: _cellSize,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final e = filtered[i];
                    return _EmojiButton(
                      tooltip: ':${e.name}:',
                      onTap: () => _pick(e.name, true),
                      child: CustomEmojiGlyph(emoji: e, size: 26),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.p.card : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? context.p.foreground : context.p.faint,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.activeId,
    required this.onPick,
  });

  final String? activeId;
  final void Function(String id) onPick;

  @override
  Widget build(BuildContext context) {
    final items = <({String id, IconData icon})>[
      (id: 'people', icon: Icons.sentiment_satisfied_alt_outlined),
      (id: 'animals', icon: Icons.pets_outlined),
      (id: 'food', icon: Icons.fastfood_outlined),
      (id: 'activities', icon: Icons.sports_soccer_outlined),
      (id: 'travel', icon: Icons.flight_outlined),
      (id: 'objects', icon: Icons.lightbulb_outline),
      (id: 'symbols', icon: Icons.favorite_border),
      (id: 'flags', icon: Icons.flag_outlined),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: items.length,
        separatorBuilder: (context, i) => const SizedBox(width: 2),
        itemBuilder: (context, i) {
          final item = items[i];
          final selected = activeId == item.id;
          return Material(
            color: selected ? context.p.card : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => onPick(item.id),
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 36,
                height: 32,
                child: Icon(
                  item.icon,
                  size: 20,
                  color: selected ? context.p.foreground : context.p.faint,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          color: context.p.faint,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmojiGrid extends StatelessWidget {
  const _EmojiGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: _EmojiPickerState._gridColumns,
      mainAxisExtent: _EmojiPickerState._cellSize,
      children: children,
    );
  }
}

class _EmojiButton extends StatelessWidget {
  const _EmojiButton({
    required this.child,
    required this.tooltip,
    required this.onTap,
  });

  final Widget child;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            width: _EmojiPickerState._cellSize,
            height: _EmojiPickerState._cellSize,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
