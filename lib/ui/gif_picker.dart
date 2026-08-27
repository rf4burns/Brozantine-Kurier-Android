import 'dart:async';

import 'package:flutter/material.dart';

import '../app/breakpoints.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../session/session_controller.dart';
import 'gif_favourite_star.dart';

/// Opens a Discord-style GIF picker. Returns the picked URL, or null if dismissed.
Future<String?> showKurierGifPicker(
  BuildContext context, {
  required SessionController session,
}) {
  final phone =
      breakpointOf(MediaQuery.sizeOf(context).width) == Breakpoint.phone;

  Widget picker({required bool compact}) => GifPicker(
    session: session,
    compact: compact,
    onSelect: (url) => Navigator.of(context).pop<String>(url),
  );

  if (phone) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(ctx).bottom),
        child: Material(
          color: ctx.p.sidebar,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.7,
            child: picker(compact: true),
          ),
        ),
      ),
    );
  }

  return showDialog<String>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: picker(compact: false),
    ),
  );
}

class GifPicker extends StatefulWidget {
  const GifPicker({
    super.key,
    required this.session,
    required this.onSelect,
    this.compact = false,
  });

  final SessionController session;
  final ValueChanged<String> onSelect;
  final bool compact;

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  static const _debounce = Duration(milliseconds: 350);

  final _search = TextEditingController();
  Timer? _timer;
  int _tab = 0;
  List<String> _urls = [];
  List<String> _favourites = [];
  bool _loading = false;
  String? _error;
  bool _noProvider = false;

  @override
  void initState() {
    super.initState();
    _favourites = widget.session.store.favoriteGifs();
    _search.addListener(_onQueryChanged);
    _fetch();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.removeListener(_onQueryChanged);
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _timer?.cancel();
    _timer = Timer(_debounce, _fetch);
  }

  Future<void> _fetch() async {
    final query = _search.text.trim();
    setState(() {
      _loading = true;
      _error = null;
      _noProvider = false;
    });
    try {
      final urls = await widget.session.searchGifs(query);
      if (!mounted) return;
      setState(() {
        _urls = urls;
        _loading = false;
        _noProvider = urls.isEmpty && widget.session.gifApiKey.isEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
        _noProvider = widget.session.gifApiKey.isEmpty;
      });
    }
  }

  Future<void> _toggleFavourite(String url) async {
    await widget.session.toggleFavoriteGif(url);
    if (!mounted) return;
    setState(() => _favourites = widget.session.store.favoriteGifs());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final l = L10n.of(context);
    final columns = widget.compact ? 2 : 3;
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Row(
            children: [
              _TabChip(
                label: l('gifSearchTab'),
                selected: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              const SizedBox(width: 8),
              _TabChip(
                label: l('gifFavourites'),
                selected: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
            ],
          ),
        ),
        if (_tab == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: TextField(
              controller: _search,
              style: TextStyle(color: p.foreground, fontSize: 14),
              decoration: InputDecoration(
                hintText: l('gifSearchPlaceholder'),
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
        Expanded(child: _body(context, l, columns)),
      ],
    );

    if (widget.compact) return child;

    return Container(
      width: 352,
      height: 420,
      decoration: BoxDecoration(
        color: p.sidebar,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.divider),
      ),
      child: child,
    );
  }

  Widget _body(BuildContext context, L10n l, int columns) {
    if (_tab == 1) {
      if (_favourites.isEmpty) {
        return _message(l('gifNoFavourites'));
      }
      return _grid(_favourites, columns);
    }
    if (_loading && _urls.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null && _urls.isEmpty) {
      return _message(l('gifSearchFailed'));
    }
    if (_urls.isEmpty) {
      return _message(_noProvider ? l('gifNoKey') : l('gifNoResults'));
    }
    return Stack(
      children: [
        _grid(_urls, columns),
        if (_loading)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _message(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.p.muted, fontSize: 13),
        ),
      ),
    );
  }

  Widget _grid(List<String> urls, int columns) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: urls.length,
      itemBuilder: (context, i) {
        final url = urls[i];
        final fav = _favourites.contains(url);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Material(
                color: context.p.rail,
                child: InkWell(
                  onTap: () => widget.onSelect(url),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Icon(
                      Icons.broken_image_outlined,
                      color: context.p.muted,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GifFavouriteStar(
                  favourited: fav,
                  onPressed: () => _toggleFavourite(url),
                ),
              ),
            ],
          ),
        );
      },
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
