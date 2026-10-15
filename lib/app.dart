import 'package:dba2/controllers/bible_controller.dart';
import 'package:dba2/core.dart';
import 'package:dba2/state/reader_audio_link.dart';
import 'package:dba2/ui/bible_reader_page.dart';
import 'package:dba2/ui/sidebar_left_navigation.dart';
import 'package:dba2/ui/sidebar_reveal.dart';
import 'package:dba2/widgets/settings/settings_page.dart';

class DavidsBibleApp2 extends StatefulWidget {
  const DavidsBibleApp2({super.key});

  @override
  State<DavidsBibleApp2> createState() => _DavidsBibleApp2State();
}

class _DavidsBibleApp2State extends State<DavidsBibleApp2> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ReaderAudioLink>().attach();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bible = context.read<BibleController>();

    return MaterialApp(
      title: "David's Bible App v2",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: context.watch<ThemeProvider>().themeMode,
      home: BibleReaderPage(
        controller: bible,
        readerScroll: bible.readerScroll, // was the separate provider
      ),
      builder: (context, child) => SidebarReveal(
        dragZoneTopInset: kToolbarHeight, // no-drag zone over the AppBar
        dragZoneBottomInset: 88, // no-drag zone over the bottom area
        openFraction: 0.92,
        fadeIn: true,
        fadeStartOpacity: 0.3,
        fadeEndOpacity: 1.0,
        leftSidebar: HeroControllerScope.none(
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => SidebarLeftContent(controller: bible),
            ),
          ),
        ),
        rightSidebar: HeroControllerScope.none(
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => SettingsPage(controller: bible),
            ),
          ),
        ),
        child: child!,
      ),
    );
  }
}
