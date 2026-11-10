import 'package:dba2/components/audio/controllers/audio_controller.dart';
import 'package:dba2/components/audio/ui/audio_bar.dart';
import 'package:dba2/core.dart';
import 'package:dba2/ui/widgets/draggable_snap_sheet.dart';

// Compact heights: pills only vs pills + seek bar.
const _compactPills = SheetSize.px(50);
const _compactPillsSeek = SheetSize.px(100);

/// Opens the audio sheet, or closes it if it is already open.
/// Call this from any button, menu or gesture.
void openAudioSheet(BuildContext context) {
  if (isModalSnapSheetOpen('audio')) {
    closeModalSnapSheet('audio');
    return;
  }
  final audio = context.read<AudioController>();

  showModalSnapSheet<void>(
    context: context,
    sheetKey: 'audio',

    positions: const SnapPositions.sized(
      min: SheetSize.px(330),
      max: SheetSize.px(330),
    ),
    tolerantContent: true,
    builder: (_) => const AudioBar(),

    // compact mode
    compactListenable: audio,
    compactWhen: () => audio.compactMode,
    unlockWhen: () => audio.unlockWhileCompact,
    // re-read on every notify, so toggling Sync resizes the sheet live
    compactSizeOf: () =>
        audio.compactShowsSeek ? _compactPillsSeek : _compactPills,
    compactHideHandle: false,
  );
}
