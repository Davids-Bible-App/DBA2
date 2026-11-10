import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class ChatTurn {
  const ChatTurn(this.role, this.content);
  final String role; // 'user' | 'assistant'
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
  factory ChatTurn.fromJson(Map<String, dynamic> j) => ChatTurn(j['role'] as String, j['content'] as String);
}

class ConversationSummary {
  ConversationSummary(this.id, this.title, this.updatedAt);
  final int id;
  String title;
  int updatedAt; // ms since epoch

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'updatedAt': updatedAt};
  factory ConversationSummary.fromJson(Map<String, dynamic> j) =>
      ConversationSummary(j['id'] as int, j['title'] as String, j['updatedAt'] as int);
}

/// Stores each conversation as an append-only JSON-Lines file (one message per
/// line), so saving a message is O(1) no matter how long the chat is.
/// Swap this class for your own SQLite/Drift code if you prefer.
class ChatRepository {
  ChatRepository._(this._dir, this._index);
  final Directory _dir;
  final List<ConversationSummary> _index;
  static const _newTitle = 'New conversation';

  static Future<ChatRepository> open(Directory root) async {
    final dir = Directory(p.join(root.path, 'bible_chats'));
    await dir.create(recursive: true);
    final index = <ConversationSummary>[];
    final f = File(p.join(dir.path, 'index.json'));
    if (await f.exists()) {
      try {
        for (final j in jsonDecode(await f.readAsString()) as List) {
          index.add(ConversationSummary.fromJson(j as Map<String, dynamic>));
        }
      } catch (_) {}
    }
    final repo = ChatRepository._(dir, index);
    repo._sort();
    return repo;
  }

  List<ConversationSummary> get conversations => List.unmodifiable(_index);

  File _file(int id) => File(p.join(_dir.path, 'chat_$id.jsonl'));
  void _sort() => _index.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> _saveIndex() async {
    final f = File(p.join(_dir.path, 'index.json'));
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_index.map((c) => c.toJson()).toList()), flush: true);
    await tmp.rename(f.path);
  }

  Future<int> create() async {
    final id = DateTime.now().millisecondsSinceEpoch;
    _index.add(ConversationSummary(id, _newTitle, id));
    _sort();
    await _saveIndex();
    return id;
  }

  Future<List<ChatTurn>> messages(int id) async {
    final f = _file(id);
    if (!await f.exists()) return const [];
    final out = <ChatTurn>[];
    for (final line in await f.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        out.add(ChatTurn.fromJson(jsonDecode(line) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  Future<void> append(int id, ChatTurn turn) async {
    await _file(id).writeAsString('${jsonEncode(turn.toJson())}\n', mode: FileMode.append, flush: true);
    final c = _index.firstWhere((c) => c.id == id);
    c.updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (turn.role == 'user' && c.title == _newTitle) {
      // First user message becomes the title (same 40-char rule as before).
      c.title = String.fromCharCodes(turn.content.replaceAll(RegExp(r'\s+'), ' ').trim().runes.take(40));
    }
    _sort();
    await _saveIndex();
  }

  Future<void> delete(int id) async {
    _index.removeWhere((c) => c.id == id);
    final f = _file(id);
    if (await f.exists()) await f.delete();
    await _saveIndex();
  }
}
