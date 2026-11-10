import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// All file_picker calls in ONE place. file_picker v13 uses static methods;
/// if a future version renames something, this is the only file to touch.
Future<List<String>> pickImagePaths() async {
  // If you only ever get one file back, add `allowMultiple: true`.
  final files = await FilePicker.pickFiles(type: FileType.image);
  return [
    for (final f in files)
      if (f.path != null) f.path!,
  ];
}

/// Returns true if the user chose a location and the file was written.
Future<bool> saveBytesAs(Uint8List bytes, String fileName) async {
  final out = await FilePicker.saveFile(
    dialogTitle: 'Save meme',
    fileName: fileName,
    bytes: bytes,
  );
  return out != null;
}
