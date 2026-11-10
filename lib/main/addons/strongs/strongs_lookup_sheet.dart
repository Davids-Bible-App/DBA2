import 'dart:async';

import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/main/addons/strongs/strongs_widgets.dart';
import 'package:dba2/ui/widgets/draggable_snap_sheet.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'strongs_lookup_controller.dart';
import 'strongs_models.dart';
import 'strongs_repository.dart';
import 'strongs_theme.dart';

// One controller for the whole app run: closing the sheet keeps the results.
StrongsLookupController? _session;

StrongsLookupController _lookup() =>
    _session ??= StrongsLookupController(StrongsRepository.instance)
      ..loadHistory();

/// Wipes the remembered lookup (text, results).
void resetStrongsLookupSession() => _session?.clear();

/// Opens the lookup as a TOP sheet.
///   showStrongsLookupSheet(context)                          // blank search
///   showStrongsLookupSheet(context, query: 'G746', origin: 'beginning')
///
/// Opened from the verse sheet it stacks on top of it, so closing it returns
/// to the verse sheet (your onSheetClose -> toggleSheet("strongs") dance).
Future<void> showStrongsLookupSheet(
  BuildContext context, {
  String? query,
  String? origin,
  BibleController? bible,
}) async {
  final b = bible ?? context.read<BibleController>();
  final c = _lookup();
  final injected = query != null && query.trim().isNotEmpty;
  if (injected) unawaited(c.search(query, origin: origin));

  await showModalSnapSheet<void>(
    context: context,
    positions: kTopSheetPositions,
    setTop: true,
    resizeContent: true,
    builder: (_) =>
        StrongsLookupSheet(controller: c, bible: b, injected: injected),
  );
}

class StrongsLookupSheet extends StatefulWidget {
  const StrongsLookupSheet({
    super.key,
    required this.controller,
    required this.bible,
    required this.injected,
  });

  final StrongsLookupController controller;
  final BibleController bible;

  /// Opened with a ready-made query: don't pop the keyboard.
  final bool injected;

  @override
  State<StrongsLookupSheet> createState() => _StrongsLookupSheetState();
}

class _StrongsLookupSheetState extends State<StrongsLookupSheet> {
  StrongsLookupController get _c => widget.controller;
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  late int _lastEpoch;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _lastEpoch = _c.resultsEpoch;
    if (!widget.injected) {
      // Wait for the slide-in, then focus + select all (the 150ms setTimeout).
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        _focus.requestFocus();
        _c.input.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _c.input.text.length,
        );
      });
    }
  }

  void _onFocus() => setState(() {}); // show / hide the history dropdown

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _run([String? text]) {
    _focus.unfocus();
    _c.search(text ?? _c.input.text);
  }

  void _goTo(VerseUsage v) {
    _focus.unfocus();
    final bible = widget.bible;
    // Close every sheet (lookup + verse sheet below it), then navigate.
    Navigator.of(context).popUntil((r) => r is! ModalSnapSheetRoute);
    bible.goTo(v.bookId, v.chapter, verse: v.verse);
  }

  String _bookName(String id) {
    for (final b in widget.bible.books) {
      if (b.id == id) return b.englishName;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    return SheetSafePadding(
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) =>
            _body(Theme.of(context), StrongsTheme.of(context)),
      ),
    );
  }

  Widget _body(ThemeData theme, StrongsTheme t) {
    if (_lastEpoch != _c.resultsEpoch) {
      _lastEpoch = _c.resultsEpoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
    final showHistory = _focus.hasFocus && _c.history.isNotEmpty;

    return Column(
      children: [
        const SheetTitle('Strongs Lookup'),
        _inputField(t),
        SizedBox(
          height: 3,
          child: _c.loading
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
        Expanded(
          child: Stack(
            children: [
              _results(theme, t),
              if (showHistory)
                Positioned(top: 0, left: 0, right: 0, child: _historyPanel(t)),
            ],
          ),
        ),
      ],
    );
  }

  // ---- text box -----------------------------------------------------------
  Widget _inputField(StrongsTheme t) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: _c.input,
      focusNode: _focus,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      onSubmitted: (_) => _run(),
      onTapOutside: (_) => _focus.unfocus(),
      decoration: InputDecoration(
        hintText: 'e.g. G746, H1254, or God',
        hintStyle: TextStyle(color: t.dimmerText, fontSize: 14),
        filled: true,
        fillColor: isDark ? Colors.black26 : Colors.black12,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.inputRadius),
          borderSide: BorderSide.none,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _c.input,
          builder: (context, v, _) => v.text.isEmpty
              ? const SizedBox.shrink()
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _c.clear();
                        _focus.requestFocus();
                      },
                    ),
                    IconButton(
                      tooltip: 'Search',
                      icon: const Icon(Icons.keyboard_return, size: 18),
                      onPressed: _run,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ---- history dropdown ---------------------------------------------------
  Widget _historyPanel(StrongsTheme t) {
    // TextFieldTapRegion: taps in here are NOT "outside" the text field, so
    // the field keeps focus and the dropdown doesn't vanish mid-tap.
    return TextFieldTapRegion(
      child: Material(
        color: t.panelBackground,
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 190),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              for (final item in _c.history)
                InkWell(
                  onTap: () => _run(item),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 10,
                          ),
                          child: Text(item, style: TextStyle(color: t.dimText)),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove from history',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => _c.removeFromHistory(item),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- results ------------------------------------------------------------
  Widget _note(String text, StrongsTheme t, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color ?? t.dimmerText,
          fontStyle: FontStyle.italic,
        ),
      ),
    ),
  );

  Widget _sectionTitle(
    String text,
    ThemeData theme,
    StrongsTheme t, {
    String? origin,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        if (origin != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(
              TextSpan(
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
                children: [
                  const TextSpan(text: '(Originating from: '),
                  TextSpan(
                    text: origin,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ')'),
                ],
              ),
            ),
          ),
        Divider(color: t.divider, height: 20),
      ],
    );
  }

  Widget _results(ThemeData theme, StrongsTheme t) {
    if (_c.error != null) return _note(_c.error!, t, color: t.noResultsColor);
    if (_c.loading) return _note('Searching database...', t);
    final data = _c.data;
    if (data == null) return const SizedBox.shrink();

    final query = _c.activeQuery ?? '';
    final bold = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        if (data.verseCount > 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text.rich(
                textAlign: TextAlign.center,
                TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.dimText),
                  children: [
                    TextSpan(text: '"$query" occurs '),
                    TextSpan(text: '${data.occurrenceCount}', style: bold),
                    TextSpan(
                      text: ' time${data.occurrenceCount != 1 ? 's' : ''} in ',
                    ),
                    TextSpan(text: '${data.verseCount}', style: bold),
                    TextSpan(text: ' verse${data.verseCount != 1 ? 's' : ''}.'),
                  ],
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _sectionTitle(
              data.isStrongsSearch
                  ? 'STRONGS DEFINITION LOOKUP'
                  : 'ENGLISH WORD MATCHES',
              theme,
              t,
              origin: _c.origin,
            ),
          ),
        ),
        if (data.dictionaries.isEmpty)
          SliverToBoxAdapter(child: _note('No dictionary definition found.', t))
        else
          SliverList.separated(
            itemCount: data.dictionaries.length,
            separatorBuilder: (_, _) => Divider(color: t.divider, height: 1),
            itemBuilder: (_, i) {
              final d = data.dictionaries[i];
              return StrongsEntry(
                def: d,
                onTagTap: () => _c.jumpToStrongs(d.strongsId),
              );
            },
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _sectionTitle('USES OF : ${query.toUpperCase()}', theme, t),
          ),
        ),
        if (data.verses.isEmpty)
          SliverToBoxAdapter(
            child: _note('No verses found containing this search.', t),
          )
        else
          SliverList.separated(
            itemCount: data.verses.length,
            separatorBuilder: (_, _) =>
                Divider(color: t.divider.withValues(alpha: 0.4), height: 1),
            itemBuilder: (_, i) {
              final v = data.verses[i];
              return _VerseRow(
                verse: v,
                label: '${_bookName(v.bookId)} ${v.chapter}:${v.verse}',
                onGo: () => _goTo(v),
                onCode: _c.jumpToStrongs,
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ONE VERSE USAGE
// ---------------------------------------------------------------------------

class _VerseRow extends StatelessWidget {
  const _VerseRow({
    required this.verse,
    required this.label,
    required this.onGo,
    required this.onCode,
  });

  final VerseUsage verse;
  final String label;
  final VoidCallback onGo;
  final void Function(String code) onCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = StrongsTheme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: onGo,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 2,
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: t.refColor,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final code in verse.strongsIds)
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => onCode(code),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: t.divider),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            code,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            verse.text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
