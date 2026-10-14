import 'dart:io' show Platform;

import 'package:just_audio_background/just_audio_background.dart';

// import 'package:just_audio_media_kit/just_audio_media_kit.dart';

Future<void> initAudioBackground() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.aver.dba2.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
    );
  }

  // if (Platform.isWindows || Platform.isLinux) {
  //   try {
  //     JustAudioMediaKit.ensureInitialized();
  //   } catch (e, st) {
  //     debugPrint('media_kit init failed: $e\n$st');
  //   }
  // }
}
