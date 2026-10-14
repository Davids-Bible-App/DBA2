import 'package:dba2/controllers/audio_controller.dart';
import 'package:dba2/controllers/bible_controller.dart';

/// Keeps the Bible reader and the audio player pointing at the same
/// book/chapter, and gives the audio controller the reader's ScrollController.
class ReaderAudioLink {
  ReaderAudioLink({required this.bible, required this.audio});

  final BibleController bible;
  final AudioController audio;

  /// Call once, after the first frame.
  void attach() {
    audio.readerScroll = bible.readerScroll;
    audio.onAudioMoved = _onAudioMoved;
    bible.addListener(_onReaderChanged);
    _onReaderChanged();
  }

  // audio -> reader
  void _onAudioMoved(int bookIndex, int chapter) {
    if (bookIndex < 0 || bookIndex >= audio.books.length) return;
    final bookId = audio.books[bookIndex].id;
    if (bible.selectedBookId != bookId || bible.selectedChapter != chapter) {
      bible.goTo(bookId, chapter);
    }
  }

  // reader -> audio
  void _onReaderChanged() {
    final book = bible.currentBook;
    if (book == null || bible.isLoading) return;

    final bookIndex = audio.books.indexWhere((b) => b.id == book.id);
    if (bookIndex == -1) return;

    audio.readerMoved(bookIndex, bible.selectedChapter);
  }

  void dispose() {
    bible.removeListener(_onReaderChanged);
    audio.onAudioMoved = null;
    audio.readerScroll = null;
  }
}
