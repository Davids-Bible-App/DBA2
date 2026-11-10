## David's bible App DBA2.v.2.0.1 Android Only (Built in Google Flutter, Not a Ported Web Browser)

### :BuildNo-0043

##### Markdown Editor:

- Removed customize Theme from Options, keep it simple.

### :BuildNo-0042

##### Search:

- Resized min sheet.
- Searchbar Input focus from min, resizes sheet to mid position.
- Pinch to zoom expand on selected verses for Uni-Verse wittnessing tool to open.

##### Markdown Editor:

- Fixed: Light/Dark switch theme customization changes, reverting to default.
- Changed Default Colors to better match theme.

### :BuildNo-0041

##### MemeMaker:

- Text Layer SelectionBox can be hidden in Layers.
- Fill/Outline Text Colors can be swapped.
- Background Layer, now shows Image when image selected, or Color.
- Export Button And Export Option Buttons, Now a Split button.
- Text Layer Fonts now load on first use, instead of interacting with font for it to show.

##### Markdown Editor:

- Paste Options moved from Toolbar to Menu, to not to confuse user operation.
- Paste Options, now allows different verse layouts.
- Added: Paste Options Previewer.

### :BuildNo-0040

##### App:

- SideBar Locking, Now Per-Side-Lock can be chosen. e.g. Editor opens to Topics, but not to Navigation.

##### Help/Docs/Info:

- Ported and now usable, First test in audio Menu as Help.

##### MenuBtn:

- Added: Better Animation than v1.. Changed Timings and Opacity.
- Backdrop now expands automatically according to number of buttons added.

### :BuildNo-0039

##### App:

- Now has MemeMaker with extra-features from v1.

##### MemeMaker:

- Also can hide and lock Text Layers.
- Text Layers can now rotate.
- Background Image, can lock and zoom.

### :BuildNo-0038

##### Search History:

- Now stored in profile.db.

##### Markdown Editor:

- Verses sent to editor: Grouped Verses can be pasted Stacked(line by line) Or Inline, Toolbar setting.
- Verses sent to editor: Verses can Auto-paste at end of doc, Or Paste at Cursor, via BadgeButton, Toolbar setting. 
- Verses sent to editor: Paste at EOF if no cursor position chosen.
- Verses sent to editor: Undo, repopulates verse to paste button.
- All State now goes to profile.db, except undo/redo history, to prevent large unneeded data passing.

### :BuildNo-0037

##### App

- Markdown Editor added.

##### Markdown Editor:

- Selected verses from Search, passed to editor.
- Selected verses from Reader, passed to editor.
- Within Topic/menu "Send to Editor" the complete Topic.
- From Search, choice of inline or verse per-row with consecutive selected verses.
- Independant Light/Dark Mode from App or System, for comfort of reading or writing.
- Full light/Dark theming, within Editor options.
- Quick Export, SaveAs, Open File.
- And Other Features.

##### Reader:

- Bigger Tap Area for FootNotes.

### :BuildNo-0036

##### AI:

- Bible Chat Now integrated with Android, and Desktop versions.
- Copy any chat segment or whole chat.
- Separate Themimg file added.
- Reply quotes and pastes the segment to Ask a Question.
- Android, swipe close, unloads the LLM gguf file from memory.
- - If Audio is playing, it will continue uninterupted, and Model will still unload.
- Windows, On App close or crash, now returns Model Memory, back to system.
- Older Devices, will not be allowed to use AI. 32bit.
- Not enough Memory for GGUF Model, will refuse to load.
- Not enabled by default, toast prompt to enable in settings.
- TopBar Audio replaced by AI button when enabled. To save space, wider devices show both.

### :BuildNo-0035

##### Reader:

- Highlights, now have Box-Highlights and Text-Highlights. See-Settings
- Sidelights added. See-Settings

##### App:

- Updated: AddOns AppFolder changed from databases to addons

### :BuildNo-0034

##### App:

- Added: Daily Streak, Longest Streak, Also now saves to profile so it can be backed up, if you need to reinstall elsewhere.
- Icon Button nudge added to all NavBar btn's, to better center them, L/D have their own nudge.
- IkonBtn nudge added to label in Top appBar, for Daily Streak Numbers, to counteract lineheight. (Vertical centering L/D)
- Fixed a shared Scroll(OT/NT NavBtns) crash, only noticable in debug?

### :BuildNo-0033

##### App:

- Added: Compare verse/verses/browse with multiple translations.
- Added: Compare Gestures, 
    Browse Prev/Next: Swipe left/right, 
    Panel Open/close: Swipe up/down, 
    Compare Close: Swipe multi-finger.
- Left SideBar, now closes on navigation swipe-left, swipe-right/left to change between OT/NT.
- The sideBars now close using [Android Back Button].
- OT/NT Buttons now update when paging chapters in Reader. Could be left stale, otherwise.

##### Audio:

- Adjusted Heights of Add Audio Sheet.
- Auto-Scroll Plus/Minus 5 lines manual scroll adjustment added.
- Fixed: On Android The Reader Page gets scrolled to the top, when DeSync'd audio changes chapter.

##### Search:

- Fixed: Multi-section reference requests, only returning first section, 
- Fixed: Omitting duplicated verses. Now: [bool dedupe = false,]

### :BuildNo-0032


##### Audio:

- DeSync and Auto-Scroll, now use a compact sheet mode.

##### Gallery:

- Swiping right now includes bookmarks -> Notes -> topic-details -> topics-list -> close-SideBar.
- topic-details -> topics-list: Tab like Page transition Animation added.

##### Gestures:

- Two-Finger-Swipe, replaced with, Swipe Left, Swipe Right.

### :BuildNo-0031

##### Audio:

- Fixed: In windows the Reader Page gets scrolled to top, when DeSync'd audio changes chapter.

##### Gallery:

- Pefecting Theme colors in Topics, Notes,Bookmarks.
- Improved Topic Dragging & DragBar-Shape&Style.

##### App:

- Sheets: now have a lot more additions, 
    See top of file, for extensive list: lib\widgets\draggable_snap_sheet.dart

### :BuildNo-0030

##### App:

- Translation Export/Import Now include Strongs and CrossRefs db's
- Replaced Translations, CrossRefs, Strongs, & History, with new snapSheet.
- Fine-tuning sheet-layouts, heights.
- Adusting text & icons & colors, within Sheet Content.

### :BuildNo-0029

##### App:

- History is now ported and integrated.
- Verse Of The Day 24h Changer, now Ported and integrated.
- New: DaggableSnapSheet, installed for Top-Down sheets(beta).
- Optomizations.

##### Gallery:

- Fixed: Topic - Drag down, moving back up one, due to a depreciated call, 
update: onReorder to onReorderItem.
- SearchBox color improvement.

##### VOTD:

- Better movement, and caching.

### :BuildNo-0028

##### App:

- Added: Body Texture can now be turned on/off.
- Added: NavBar Textures can now be turned on/off, per-NavBar.
- Added: Gestures to return the last Cross-Ref Lookup via NavBars.
- Cross-References Now Fully Integrated with ability to Download/Upload Database.
- SnackBars, replaced by toasts.
- Color adjustments when no textures.

### :BuildNo-0027

##### App:

- Strongs Dictionary, Basic port from Tauri2, needs work...
- Strongs Database Fully Integrated with ability to Download/Upload.

##### App:

- Changed icon again...

##### Audio:

- Android Media-Tray, added Double_Clef Note svg.

### :BuildNo-0026
##### App:

- Changed icon.
- Added: Name and Git URL to About.

##### NavBars:

- Added: Textured NavBars for testing.

##### Search:

- Added: Open from Bottom-Nav Menu-Buttons.
- Added: NavBars, Open from Gestures.

### :BuildNo-0025

##### Verse Of The Day VOTD:

- Image Animation, paused while sidebar closed.

##### Audio:

- Timer and Audio, animations stop if not visible to the user, or screen-locked. Battery Optomizations.
- Auto-scroll reader while audio playing, Now turns off, on app change, or screen-lock.

### :BuildNo-0024

##### Search:

- Added Search, as in v1.

### :BuildNo-0023

##### Profile:

- Import profile.db auto refresh, to show Topics, Notes, Bookmarks.

##### Audio:

- AudioController: upgraded depreciated calls. "ConcatenatingAudioSource? _concat;"

##### Gallery:

- Upgraded onIndex to onIndaxItem, depreciated calls in Notes, Topics.
- Bookmarks now use the same Searchbar as Topics & Notes.
- Fixed Topic addTo or Update Dialog, submitting not editing.
- Updated Theme...

##### Uni-Verse:

- Now Fully working and themed.

### :BuildNo-0022

##### Profile:

- Topics, Notes, Bookmarks, Now persisted to database.

##### Settings:

- Can Now Reset All Settings, usefull when importing DBAv1 profiles, as a lot of saved settings are now not needed.
- Added some default Navbar gestures, but can easily be cleared, Any changes you make save to profile instantly.

##### MenuBtn:

- Can now tap the label, not just the button.

### :BuildNo-0021

##### Profile:

- Added: Profile Database Integration
- Highlights Save.
- Theme Saves.
- Sticky chapter Heading Saves.
- Personalization Name Saves.
- Top/Bottom Navbar Gestures Save.

##### Settings:

- Added: Import/Export Profile Database, Import Can Replace or Merge by newest timestame.

### :BuildNo-0020

##### Audio:

- Fixed: Crash, if Loop Mode was Book, and the Android Media controls tried to traverse the book boundry.

##### Reader:

- Added: Note Tap, animated expand/collapse.

##### Notes:

- Fixed: In Notes Tab, in-Note-Edit keyboard comes up, Could close side-bar and keyboard remains.
- Fixed: Can have many note editmodes open together, Now Single edit only.
- Fixed: If Note to Edit, is at the bottom of the screen, the keyboard covers the note, instead of pushing it up into view.

### :BuildNo-0019

##### Right-Sidebar-Content:

- Fits within Android Safe-Area.

##### Gallery:

- Notes, updated to work as in v1.
- Can now swipe between tabs.
- Cannot close tab or open tabs while any dialog is open.
- Android keyboard, is dismissed when changing tab.

##### Reader:

- Added, Note tap in Reader, expands to show Note, DoubleClick or Long-Press to edit.
- DropCap_-_first-Letter, Now becomes Italic as the original, as in Psalms.

### :BuildNo-0018

This Build remains as 0017, nothing new added.

##### Folder Structure:

- Reorganized 75 files.
- Removed all file heading filepath comments

### :BuildNo-0017

##### Right-Sidebar-Content:

- Added Gallery.

##### Gallery:

- Added Bookmarks.
- Added Topics.
- Added Notes.
- Added Uni-Verse Witnessing Tool, for Topical Verse Presentation.

### :BuildNo-0016

##### Right-Sidebar-Content:

- Removed Settings, now only within bottom-sheet.
- Added calls to Settings and AudioPlayer in Bottombar right MenuBtn.

##### Settings:

- Switch Theme Changes.
- Name Personalization.
- About Page & License.

##### Audio:

- New Controller added, replaced two, unmaintained plugins.
- Android Media-tray Controls, Now Navigate Books Not just Chapters, with both Prev/Next.
- New Audio Setting, in settings page, 'On Bible End', restart Book/NT/OT or stop.

##### Theme:

- Updates to settings theme.

### :BuildNo-0015

##### Theme:

- Updates to theme colors.
- Some Reusable Widgets added to global theme space.
- Settings page, re-done in Material3 theme.
- Navbars, buttons Nue look.

### :BuildNo-0014

##### Audio Bibles:

- Improved Save Audio Bible To Local disk Dialog.
- Updated URLs with Fast download links to the Audio-Bibles.

### :BuildNo-0013

##### Icons:

- Different icons, colors, sizes, positions.

##### Audio Bibles:

- Ability to download Audio-Bibles from online, and backup locally for offline restore.

### :BuildNo-0012

##### Translations:

- Deleting a translation gives option to save it locally.
- Export Button, exports the Bibles folder in appData to a zip file.
- Import allows importing from, .db, .dba, and multiple translations in .zip files.

##### Reader:

- Can Now Split-view Two Bible-translations.

### :BuildNo-0011

##### Translations:

- Ships without the eng_kjv.db, 40MB smaller
- First run prompts to download, or upload a bible translation.
- 

### :BuildNo-(0001-0010)

##### Reader:

- Fast opening Sidebars, no stutter.
- Light/Dark Theme.

##### Highlights:

- Integrated as in v.1 (Not yet Persistent, No Profile DB yet)

##### Settings:

- Light/Dark/System
- Swipe/DoubleClick/Etc. Top/Bottom Gestures for opening, running widgets.
- Chapter Sticky Header

##### Audio:

- Fully Working Audio, with Reader Sync/Desync, as in v.1...
- Smooth AutoScroll.
- SeekBar Brings Reader-Text with it.
- Slight UI changes.
- Improved UI for Audio Bible Import.