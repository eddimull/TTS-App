import 'package:flutter/cupertino.dart';
import '../../songs/screens/song_list_screen.dart';
import 'library_screen.dart';

enum LibraryTabSegment { songList, sheetMusic }

/// The Library tab: a segmented control switching between the band's song
/// list and the sheet-music library. The tab keeps its "Library" name and
/// icon; the Sheet music segment renders the existing [LibraryScreen]
/// unchanged below the segment.
class LibraryTabScreen extends StatefulWidget {
  const LibraryTabScreen({super.key});

  @override
  State<LibraryTabScreen> createState() => _LibraryTabScreenState();
}

class _LibraryTabScreenState extends State<LibraryTabScreen> {
  LibraryTabSegment _segment = LibraryTabSegment.songList;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<LibraryTabSegment>(
                  groupValue: _segment,
                  onValueChanged: (value) {
                    if (value != null) setState(() => _segment = value);
                  },
                  children: const {
                    LibraryTabSegment.songList: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Song list'),
                    ),
                    LibraryTabSegment.sheetMusic: Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('Sheet music'),
                    ),
                  },
                ),
              ),
            ),
            Expanded(
              child: _segment == LibraryTabSegment.songList
                  ? const SongListScreen()
                  : const LibraryScreen(),
            ),
          ],
        ),
      ),
    );
  }
}
