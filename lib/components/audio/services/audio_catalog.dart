// DEVELOPER: this is the only file you edit to add / change downloadable audio.
import 'dart:convert';
import 'dart:io';

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

class AudioPack {
  const AudioPack({
    required this.name,
    required this.url,
    this.description = '',
    this.sizeMb,
    this.aliases = const [], // other spellings of the _meta.txt author name
  });

  final String name;
  final String url;
  final String description;
  final int? sizeMb;
  final List<String> aliases;

  /// The installed author folder that matches this pack, or null.
  String? installedAs(List<String> authors) {
    final wanted = {_norm(name), ...aliases.map(_norm)};
    for (final a in authors) {
      if (wanted.contains(_norm(a))) return a;
    }
    return null;
  }

  factory AudioPack.fromJson(Map<String, dynamic> j) => AudioPack(
    name: j['name'] as String,
    url: j['url'] as String,
    description: (j['description'] as String?) ?? '',
    sizeMb: (j['sizeMb'] as num?)?.toInt(),
    aliases: ((j['aliases'] as List?) ?? const []).cast<String>(),
  );
}

/// OPTIONAL: point this at a JSON file you host, to change links or add new
/// versions WITHOUT shipping an app update. Leave '' to use only the list below.
/// Format: [{"name":"...","url":"...","description":"...","sizeMb":250}, ...]
const kCatalogUrl = ''; // e.g. 'https://yourdomain.com/audio/catalog.json'

/// Built-in list. Used offline, or when kCatalogUrl is empty or fails.
const kBuiltInCatalog = <AudioPack>[
  AudioPack(
    name: 'Alexander Scourby',
    url: 'https://github.com/Davids-Bible-App/DBA2/releases/download/DBA2/Scourby.zip',
    description: 'King James Bible, Read By Alexander Scourby, m4a',
    sizeMb: 801,
  ),
  AudioPack(
    name: 'Max McClean',
    url: 'https://github.com/Davids-Bible-App/DBA2/releases/download/DBA2/McClean.zip',
    description: 'King James Bible, Read By Max Mclean, m4a',
    sizeMb: 863,
  ),
  AudioPack(
    name: 'ESV Audio Bible',
    url: 'https://github.com/Davids-Bible-App/DBA2/releases/download/DBA2/ESVaudio.zip',
    description: 'English Standard version, Read By Unknown Author, m4a',
    sizeMb: 803,
  ),
];

Future<List<AudioPack>> loadCatalog() async {
  if (kCatalogUrl.isEmpty) return kBuiltInCatalog;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(Uri.parse(kCatalogUrl));
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return kBuiltInCatalog;
    final body = await res.transform(utf8.decoder).join();
    final list = (jsonDecode(body) as List)
        .map((e) => AudioPack.fromJson(e as Map<String, dynamic>))
        .toList();
    return list.isEmpty ? kBuiltInCatalog : list;
  } catch (_) {
    return kBuiltInCatalog; // offline etc.
  } finally {
    client.close(force: true);
  }
}
