import 'dart:io' show Platform;

import 'package:just_audio_background/just_audio_background.dart';

Future<void> initAudioBackground() async {
  if (Platform.isAndroid || Platform.isIOS) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.aver.dba2.audio',
      androidNotificationChannelName: 'Audio playback',
      // androidNotificationIcon: 'mipmap/launcher_icon',
      androidNotificationIcon: 'drawable/ic_stat_music_note',
      androidNotificationOngoing: true,
    );
  }
}
