import 'dart:async';
import 'dart:math';

import 'package:dba2/ui/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ai_exception.dart';
import '../ai_services.dart';
import '../chat_repository.dart';
import '../llm_engine.dart';
import 'confirm_dialog.dart';
import 'engine_install_banner.dart';
import 'model_manager_dialog.dart';
import 'chat_style.dart';

import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

const _greeting = 'Ask me anything about the Bible.';
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// One chat message. The text lives in a ValueNotifier so that while a reply
/// streams in, ONLY that bubble rebuilds, not the whole list or the page.
class _Msg {
  _Msg(this.role, String text) : text = ValueNotifier(text);
  final String role;
  final ValueNotifier<String> text;
}

class BibleChatPage extends StatefulWidget {
  const BibleChatPage({super.key, required this.ai});
  final AiServices ai;

  @override
  State<BibleChatPage> createState() => _BibleChatPageState();
}

class _BibleChatPageState extends State<BibleChatPage> {
  AiServices get ai => widget.ai;

  final _messages = <_Msg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();
  StreamSubscription<String>? _sub;
  Completer<void>? _streamDone;
  int? _currentId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _stop();
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _newChat() {
    if (_busy) return;
    _input.clear();
    setState(() {
      _currentId = null;
      _messages.clear();
      _error = null;
    });
  }

  Future<void> _openConversation(int id) async {
    if (_busy) return;
    Navigator.of(context).pop(); // close the drawer
    final history = await ai.chats.messages(id);
    if (!mounted) return;
    _input.clear();
    setState(() {
      _currentId = id;
      _messages
        ..clear()
        ..addAll(history.map((t) => _Msg(t.role, t.content)));
      _error = null;
    });
  }

  Future<void> _deleteConversation(int id) async {
    final sure = await confirmDialog(
      context,
      title: 'Delete conversation',
      message: "Delete this conversation? This can't be undone.",
    );
    if (!sure || !mounted) return;
    try {
      await ai.chats.delete(id);
      if (_currentId == id) _newChat();
      setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't delete that conversation.");
      }
    }
  }

  void _toast(String message) => showToast(message);

  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _toast('Copied');
  }

  void _copyChat() {
    final text = _messages
        .map(
          (m) => '${m.role == 'user' ? 'You' : 'Bible AI'}:\n${m.text.value}',
        )
        .join('\n\n');
    Clipboard.setData(ClipboardData(text: text));
    _toast('Whole chat copied');
  }

  /// Puts the message into the input box as a quote, ready to add to.
  void _quote(String text) {
    final quoted = text.trim().split('\n').map((l) => '> $l').join('\n');
    final existing = _input.text.trimRight();
    final next = existing.isEmpty ? '$quoted\n\n' : '$existing\n\n$quoted\n\n';
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _inputFocus.requestFocus();
  }

  void _stop() {
    _sub?.cancel(); // closes the HTTP request; llama-server stops generating
    final d = _streamDone;
    if (d != null && !d.isCompleted) d.complete();
  }

  void _close() => Navigator.of(context).maybePop();

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy || ai.engine.status != EngineStatus.ready) return;
    _input.clear();

    // History is taken BEFORE we add the new messages. The greeting is UI-only
    // and never sent (chat templates like Gemma's reject a leading assistant turn).
    final history = [for (final m in _messages) ChatTurn(m.role, m.text.value)];
    final reply = _Msg('assistant', '');
    setState(() {
      _error = null;
      _busy = true;
      _messages
        ..add(_Msg('user', text))
        ..add(reply);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0); // list is reversed: 0 == bottom

    final buf = StringBuffer();
    final clock = Stopwatch()..start();
    try {
      // Lazily create the conversation on the first message of a new chat.
      final id = _currentId ??= await ai.chats.create();
      await ai.chats.append(id, ChatTurn('user', text));

      final done = _streamDone = Completer<void>();
      _sub = ai.engine
          .chat(text, history)
          .listen(
            (token) {
              buf.write(token);
              // Push to the UI at most every ~40 ms instead of once per token.
              if (clock.elapsedMilliseconds >= 40) {
                reply.text.value = buf.toString();
                clock.reset();
              }
            },
            onError: (Object e, StackTrace s) {
              if (!done.isCompleted) done.completeError(e, s);
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          );
      await done.future;
      if (buf.isNotEmpty) {
        await ai.chats.append(id, ChatTurn('assistant', buf.toString()));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e, 'Something went wrong generating a reply.');
          if (buf.isEmpty) {
            _messages.remove(reply); // drop the empty placeholder
          }
        });
      }
    } finally {
      reply.text.value = buf.toString(); // flush the final tail
      _sub = null;
      _streamDone = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ChatStyle.of(context);
    final md = _markdownStyle(context, s); // once, not per streamed token

    // Esc closes the chat on Windows. Android uses the Back button.
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: s.background,
          appBar: AppBar(
            backgroundColor: s.appBar,
            foregroundColor: s.appBarText,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            title: Text(
              'Bible AI',
              style: TextStyle(fontFamily: s.fontFamily),
            ),
            leading: Builder(
              builder: (ctx) => IconButton(
                tooltip: 'History',
                icon: const Icon(Icons.history),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'New chat',
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: _busy ? null : _newChat,
              ),
              IconButton(
                tooltip: 'Copy whole chat',
                icon: const Icon(Icons.copy_all),
                onPressed: _messages.isEmpty || _busy ? null : _copyChat,
              ),
              IconButton(
                tooltip: 'Models',
                icon: const Icon(Icons.memory),
                onPressed: () => ModelManagerDialog.show(context, ai),
              ),
              IconButton(
                tooltip: 'Close (Esc)',
                icon: const Icon(Icons.close),
                onPressed: _close,
              ),
            ],
          ),
          drawer: _buildHistoryDrawer(s),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(child: _buildMessages(s, md)),
                _buildStatus(),
                _buildInput(s),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessages(ChatStyle s, MarkdownStyleSheet md) {
    // reverse:true makes index 0 the BOTTOM item, so the list stays pinned to
    // the newest message with no manual scroll code, and ListView.builder only
    // builds the bubbles that are on screen.
    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        padding: const EdgeInsets.all(12),
        itemCount: _messages.length + 1,
        itemBuilder: (context, i) {
          if (i == _messages.length) {
            return _Bubble(
              style: s,
              isUser: false,
              child: Text(_greeting, style: _textStyle(s, s.aiText)),
            );
          }
          final m = _messages[_messages.length - 1 - i];
          return _MessageRow(
            key: ObjectKey(m),
            msg: m,
            style: s,
            markdown: md,
            showTyping: _busy && i == 0,
            onCopy: _copyText,
            onQuote: _quote,
          );
        },
      ),
    );
  }

  Widget _buildStatus() {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: ai.engine,
      builder: (context, _) {
        final e = ai.engine;
        final status = switch (e.status) {
          EngineStatus.unloaded =>
            e.installed
                ? (e.resumeFilename != null
                      ? 'Model unloaded to free memory.'
                      : 'No model loaded.')
                : null,
          EngineStatus.loading => 'Loading model — this can take a little while for a large GGUF file…',
          EngineStatus.error => 'Model failed to load: ${e.lastError}',
          EngineStatus.ready => null,
        };
        Widget banner(String text, Color bg, Color fg, {Widget? action}) =>
            Container(
              width: double.infinity,
              color: bg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(text, style: TextStyle(color: fg, fontSize: 13)),
                  ?action,
                ],
              ),
            );
        return Column(
          children: [
            if (ai.installer != null)
              EngineInstallBanner(engine: e, installer: ai.installer!),
            if (status != null)
              banner(
                status,
                e.status == EngineStatus.error
                    ? cs.errorContainer
                    : cs.surfaceContainerHigh,
                e.status == EngineStatus.error
                    ? cs.onErrorContainer
                    : cs.onSurfaceVariant,
                action: e.status == EngineStatus.unloaded
                    ? (e.resumeFilename != null
                          ? TextButton(
                              onPressed: () => unawaited(
                                ai.useModel(e.resumeFilename!).catchError((
                                  Object err,
                                ) {
                                  if (mounted) {
                                    _toast(
                                      errorMessage(
                                        err,
                                        "Couldn't reload the model.",
                                      ),
                                    );
                                  }
                                }),
                              ),
                              child: const Text('Reload'),
                            )
                          : TextButton(
                              onPressed: () =>
                                  ModelManagerDialog.show(context, ai),
                              child: const Text('Open Models'),
                            ))
                    : null,
              ),
            if (_error != null)
              banner(_error!, cs.errorContainer, cs.onErrorContainer),
          ],
        );
      },
    );
  }

  Widget _buildInput(ChatStyle s) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(s.bubbleRadius),
      borderSide: BorderSide(color: c, width: w),
    );

    return ListenableBuilder(
      listenable: ai.engine,
      builder: (context, _) {
        final ready = ai.engine.status == EngineStatus.ready;
        return Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _send();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    enabled: ready,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    cursorColor: s.accent,
                    style: _textStyle(s, s.inputText),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: s.inputFill,
                      hintStyle: _textStyle(s, s.inputHint),
                      border: border(s.inputBorder),
                      enabledBorder: border(s.inputBorder),
                      disabledBorder: border(
                        s.inputBorder.withValues(alpha: 0.5),
                      ),
                      focusedBorder: border(s.accent, 2),
                      hintText: ready
                          ? 'Ask a question about scripture…'
                          : 'Waiting for model…',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_busy)
                FilledButton.tonal(onPressed: _stop, child: const Text('Stop'))
              else
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _input,
                  builder: (context, v, _) => FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: s.accent,
                      foregroundColor: s.onAccent,
                    ),
                    onPressed: ready && v.text.trim().isNotEmpty ? _send : null,
                    child: const Text('Send'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryDrawer(ChatStyle s) {
    final items = ai.chats.conversations;
    return Drawer(
      backgroundColor: s.drawer,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: items.isEmpty
            ? Center(
                child: Text(
                  'No past conversations yet.',
                  style: _textStyle(s, s.aiText),
                ),
              )
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final c = items[i];
                  final d = DateTime.fromMillisecondsSinceEpoch(c.updatedAt);
                  return ListTile(
                    selected: c.id == _currentId,
                    selectedTileColor: s.aiBubble,
                    textColor: s.aiText,
                    iconColor: s.actionIcon,
                    title: Text(
                      c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${_months[d.month - 1]} ${d.day}'),
                    onTap: () => _openConversation(c.id),
                    trailing: IconButton(
                      tooltip: 'Delete conversation',
                      icon: const Icon(Icons.close),
                      onPressed: () => _deleteConversation(c.id),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

TextStyle _textStyle(ChatStyle s, Color color) => TextStyle(
  color: color,
  fontSize: s.fontSize,
  fontFamily: s.fontFamily,
  height: 1.35,
);

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    super.key,
    required this.msg,
    required this.style,
    required this.markdown,
    required this.showTyping,
    required this.onCopy,
    required this.onQuote,
  });
  final _Msg msg;
  final ChatStyle style;
  final MarkdownStyleSheet markdown;
  final bool showTyping;
  final void Function(String text) onCopy;
  final void Function(String text) onQuote;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    return ValueListenableBuilder<String>(
      valueListenable: msg.text,
      builder: (context, text, _) {
        final Widget content;
        if (text.isEmpty && showTyping) {
          content = TypingDots(color: style.aiText.withValues(alpha: 0.6));
        } else if (isUser) {
          content = Text(text, style: _textStyle(style, style.userText));
        } else {
          content = MarkdownBody(data: text, styleSheet: markdown);
        }
        final showActions = !showTyping && text.isNotEmpty;
        return Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            _Bubble(style: style, isUser: isUser, child: content),
            if (showActions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionIcon(
                      icon: Icons.copy_outlined,
                      tooltip: 'Copy',
                      color: style.actionIcon,
                      onTap: () => onCopy(text),
                    ),
                    _ActionIcon(
                      icon: Icons.reply,
                      tooltip: 'Reply (add to message box)',
                      color: style.actionIcon,
                      onTap: () => onQuote(text),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon),
    iconSize: 18,
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    color: color,
    onPressed: onTap,
  );
}

/// Built once per page build and shared by every reply bubble.
MarkdownStyleSheet _markdownStyle(BuildContext context, ChatStyle s) {
  final body = _textStyle(s, s.aiText);
  TextStyle heading(double scale) =>
      body.copyWith(fontSize: s.fontSize * scale, fontWeight: FontWeight.w700);
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: body,
    a: body.copyWith(
      color: s.accent,
      decoration: TextDecoration.underline,
    ),
    strong: body.copyWith(fontWeight: FontWeight.w700),
    em: body.copyWith(fontStyle: FontStyle.italic),
    h1: heading(1.4),
    h2: heading(1.25),
    h3: heading(1.1),
    listBullet: body,
    blockquote: body,
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: s.fontSize - 2,
      color: s.aiText,
      backgroundColor: s.codeBackground,
    ),
    codeblockDecoration: BoxDecoration(
      color: s.codeBackground,
      borderRadius: BorderRadius.circular(8),
    ),
    blockquoteDecoration: BoxDecoration(
      color: s.codeBackground,
      borderRadius: BorderRadius.circular(6),
      border: Border(left: BorderSide(color: s.quoteBar, width: 3)),
    ),
    tableBorder: TableBorder.all(color: s.quoteBar),
    tableHead: body.copyWith(fontWeight: FontWeight.w700),
    tableBody: body,
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.style,
    required this.isUser,
    required this.child,
  });
  final ChatStyle style;
  final bool isUser;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary: a streaming bubble repaints without its neighbours.
    return RepaintBoundary(
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: min(
              MediaQuery.sizeOf(context).width * style.bubbleWidthFactor,
              640,
            ),
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isUser ? style.userBubble : style.aiBubble,
              borderRadius: BorderRadius.circular(style.bubbleRadius),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class TypingDots extends StatefulWidget {
  const TypingDots({super.key, required this.color});
  final Color color;
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Opacity(
                opacity: 0.35 + 0.65 * _wave((_c.value - i * 0.15) % 1.0),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _wave(double t) => t < 0.5 ? t * 2 : (1 - t) * 2;
}
