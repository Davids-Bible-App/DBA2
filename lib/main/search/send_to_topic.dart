import 'package:dba2/main/gallery/gallery_controller.dart';
import 'package:dba2/main/gallery/gallery_dialogs.dart';
import 'package:dba2/main/gallery/models.dart';
import 'package:dba2/main/gallery/verse_grouping.dart';
import 'package:dba2/main/controllers/bible_controller.dart';
import 'package:dba2/ui/widgets/toast.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'search_logic.dart';

/// Search "Send to Topic": converts the selected hits to GalleryEntry rows,
/// asks which topic (your existing dialog), then saves them.
///
/// Pass the context of the screen that opened the search sheet; it is still
/// mounted after the sheet closes.
/// Returns true if the verses were saved, false if cancelled / nothing to do.
Future<bool> sendHitsToTopic(BuildContext context, List<SearchHit> hits) async {
  if (hits.isEmpty) return false;

  // Grab everything that needs `context` BEFORE the first await.
  final gallery = context.read<GalleryController>();
  final bible = context.read<BibleController>();

  String bookName(String id) {
    for (final b in bible.books) {
      if (b.id == id) return b.englishName;
    }
    return id;
  }

  // translationId has no ".dba"; the repository adds it when saving.
  final entries = [
    for (final h in hits)
      GalleryEntry(
        id: 0, // not stored yet
        entryType: 'topic',
        translationId: bible.translationId,
        bookId: h.bookId,
        bookName: bookName(h.bookId),
        chapter: h.chapter,
        verseId: h.verse,
        text: h.plainText,
      ),
  ];

  // "John 3:16-17, Romans 8:1 (KJV)"; hits arrive in Bible order already.
  final groups = groupConsecutive(entries);
  final shown = groups.take(3).map(refLabel).join(', ');
  final more = groups.length > 3 ? ' … +${groups.length - 3} more' : '';
  final refText = '$shown$more (${bible.edition})';

  debugPrint('[search] opening topic dialog for: $refText');
  final topic = await showTopicDialog(
    context,
    existing: gallery.topics.map((t) => t.topic).toList(),
    refText: refText,
  );
  debugPrint('[search] topic dialog returned: $topic');
  if (topic == null) return false; // cancelled

  final used = await gallery.addToTopic(topic, entries);
  debugPrint('[search] saved ${entries.length} verses to "$used"');

  showToast(
    'Added ${entries.length} verse${entries.length == 1 ? '' : 's'} '
    'to "$used"',
  );
  return true;
}
