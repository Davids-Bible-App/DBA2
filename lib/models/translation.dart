/// ---------------------------------------------------------------------------
/// TRANSLATION CATALOG
///
/// To add a new translation when it becomes available: add ONE line to
/// [kTranslations] and upload `<id>.dba` to [kTranslationBaseUrl].
/// Nothing else in the app needs to change.
/// ---------------------------------------------------------------------------

/// Where the downloadable `.dba` files live (must end with '/').
const String kTranslationBaseUrl =
    'https://raw.githubusercontent.com/Davids-Bible-App/DavidsBibleApp.github/main/Translations/';

/// Offered on the "no Bible installed" placeholder.
const String kDefaultTranslationId = 'eng_kjv';

/// File extension used by the database files (same as your other app).
const String kTranslationExt = '.dba';

class Translation {
  const Translation(
    this.id,
    this.abbr,
    this.name,
    this.language, {
    this.url,
  });

  /// File stem, e.g. `eng_kjv` -> `eng_kjv.dba`.
  final String id;

  /// 3-4 letters shown on the ribbon.
  final String abbr;
  final String name;
  final String language;

  /// Optional override when this one is hosted somewhere else.
  final String? url;

  String get fileName => '$id$kTranslationExt';
  String get downloadUrl => url ?? '$kTranslationBaseUrl$fileName';
}

// Edit names/abbreviations freely - the id (file name) is what matters.
const List<Translation> kTranslations = [
  // English
  Translation('eng_kjv', 'KJV', 'King James Version', 'English'),
  Translation('eng_kj21', 'KJ21', '21st Century King James', 'English'),
  Translation('eng_1611', '1611', 'King James 1611', 'English'),
  Translation('eng_asv', 'ASV', 'American Standard 1901', 'English'),
  Translation('eng_bsb', 'BSB', 'Berean Standard Bible', 'English'),
  Translation('eng_dby', 'DBY', 'Darby Translation', 'English'),
  Translation('eng_dra', 'DRA', 'Douay-Rheims 1899', 'English'),
  Translation('eng_esv', 'ESV', 'English Standard Version', 'English'),
  Translation('eng_f35', 'F35', 'F35 (Family 35 NT)', 'English'),
  Translation('eng_glw', 'GLW', 'God\'s Living word', 'English'),
  Translation('eng_gnv', 'GNV', 'Geneva Bible 1599', 'English'),
  Translation('eng_net', 'NET', 'New English Translation', 'English'),
  Translation('eng_niv', 'NIV', 'New International Version', 'English'),
  Translation('eng_webp', 'WEB', 'World English Bible', 'English'),
  Translation('eng_ylt', 'YLT', "Young's Literal Translation", 'English'),
  // Other languages
  Translation('pol_ubg', 'UBG', 'Updated Gdansk Bible', 'Polski'),
  Translation('pol_bib', 'BIB', 'Polish OPLNT', 'Polski'),
  Translation('kor_old', 'KOR', 'Korean Bible 1910', 'Korean'),
];

/// Catalog lookup. Unknown ids (files the user imported) get a generated
/// entry so they still work: `eng_xyz` -> abbr `XYZ`.
Translation translationFor(String id) {
  for (final t in kTranslations) {
    if (t.id == id) return t;
  }
  final tail = id.contains('_') ? id.split('_').last : id;
  final abbr = tail.length > 4 ? tail.substring(0, 4) : tail;
  return Translation(id, abbr.toUpperCase(), id, 'Imported');
}
