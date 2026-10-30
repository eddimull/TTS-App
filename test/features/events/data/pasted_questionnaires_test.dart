import 'package:flutter_test/flutter_test.dart';
import 'package:tts_bandmate/features/events/data/pasted_questionnaires.dart';

const _block1 = '''----------
Customer submitted "Wedding Day Questionnaire" on Oct 20
== Bride and Groom Information ==
Bride / Groom: Grace Terreson
Venue name: Il Mercato
== First Dances ==
First dance: Forever and Ever, Amen''';

const _block2 = '''----------
Customer submitted "Song Request Form" on Oct 22
== Must Play ==
Must-play: Boogie Wonderland''';

void main() {
  group('parsePastedQuestionnaires', () {
    test('plain notes have no blocks', () {
      final r = parsePastedQuestionnaires('Load in at 3.\nBring the keys.');
      expect(r.bandNotes, 'Load in at 3.\nBring the keys.');
      expect(r.blocks, isEmpty);
    });

    test('empty notes', () {
      final r = parsePastedQuestionnaires('');
      expect(r.bandNotes, '');
      expect(r.blocks, isEmpty);
    });

    test('one block with sections', () {
      final r = parsePastedQuestionnaires(_block1);
      expect(r.bandNotes, '');
      expect(r.blocks, hasLength(1));
      final b = r.blocks.single;
      expect(b.name, 'Wedding Day Questionnaire');
      expect(b.date, 'Oct 20');
      expect(b.sections.map((s) => s.label),
          ['Bride and Groom Information', 'First Dances']);
      expect(b.sections.first.lines,
          ['Bride / Groom: Grace Terreson', 'Venue name: Il Mercato']);
      expect(b.answerCount, 3);
    });

    test('two blocks split at the second header', () {
      final r = parsePastedQuestionnaires('$_block1\n\n$_block2');
      expect(r.blocks.map((b) => b.name),
          ['Wedding Day Questionnaire', 'Song Request Form']);
      expect(r.blocks[0].sections, hasLength(2));
      expect(
          r.blocks[1].sections.single.lines, ['Must-play: Boogie Wonderland']);
      expect(r.bandNotes, '');
    });

    test('band notes before and after a block are kept', () {
      // A block runs to the next header or the end, so "after" text can only
      // survive when a second block ends the first; here it joins the block.
      final r = parsePastedQuestionnaires('Before the block.\n\n$_block1');
      expect(r.bandNotes, 'Before the block.');
      expect(r.blocks, hasLength(1));
    });

    test('text after the last block header belongs to the block', () {
      final r = parsePastedQuestionnaires('Intro\n$_block2\nTrailing line');
      expect(r.bandNotes, 'Intro');
      expect(r.blocks.single.sections.single.lines,
          ['Must-play: Boogie Wonderland', 'Trailing line']);
    });

    test('block with no == headers gets one Answers section', () {
      final r = parsePastedQuestionnaires(
          '----------\nCustomer submitted "Quick Form" on Nov 1\nColors: pink\nAttire: black');
      final b = r.blocks.single;
      expect(b.sections, hasLength(1));
      expect(b.sections.single.label, 'Answers');
      expect(b.sections.single.lines, ['Colors: pink', 'Attire: black']);
      expect(b.answerCount, 2);
    });

    test('dashes without a Customer submitted line are ordinary notes', () {
      const text = 'Setlist\n----------\nSong one';
      final r = parsePastedQuestionnaires(text);
      expect(r.blocks, isEmpty);
      expect(r.bandNotes, text);
    });

    test('CRLF line endings are handled', () {
      final r = parsePastedQuestionnaires(_block2.replaceAll('\n', '\r\n'));
      expect(r.blocks, hasLength(1));
      expect(r.blocks.single.name, 'Song Request Form');
    });

    test('empty section with a header is kept', () {
      final r = parsePastedQuestionnaires(
          '----------\nCustomer submitted "F" on Nov 1\n== Empty ==\n== Full ==\nA: b');
      expect(r.blocks.single.sections.map((s) => s.label), ['Empty', 'Full']);
    });
  });

  group('removePastedBlock', () {
    test('removes only the chosen block', () {
      const notes = 'Before.\n\n$_block1\n\n$_block2\n';
      final parsed = parsePastedQuestionnaires(notes);
      final after = removePastedBlock(notes, parsed.blocks.first);
      expect(after, 'Before.\n\n$_block2');
      final reparsed = parsePastedQuestionnaires(after);
      expect(reparsed.blocks.single.name, 'Song Request Form');
      expect(reparsed.bandNotes, 'Before.');
    });

    test('removing a trailing block leaves the band notes', () {
      const notes = 'Keep me.\n\n$_block1';
      final after = removePastedBlock(
          notes, parsePastedQuestionnaires(notes).blocks.single);
      expect(after, 'Keep me.');
    });

    test('removing the only block leaves an empty string', () {
      final after = removePastedBlock(
          _block1, parsePastedQuestionnaires(_block1).blocks.single);
      expect(after, '');
    });

    test('text on both sides of a middle block is rejoined', () {
      const notes = 'Top\n\n\n$_block1\n\n$_block2';
      final parsed = parsePastedQuestionnaires(notes);
      final after = removePastedBlock(notes, parsed.blocks.last);
      expect(after.startsWith('Top\n\n'), isTrue);
      expect(parsePastedQuestionnaires(after).blocks, hasLength(1));
    });
  });

  group('findPastedBlock', () {
    test('finds the block again after the notes above it changed', () {
      const before = 'Old.\n\n$_block1\n\n$_block2';
      final block = parsePastedQuestionnaires(before).blocks.last;
      const after = 'Edited elsewhere.\nTwo lines now.\n\n$_block1\n\n$_block2';
      final found = findPastedBlock(after, block);
      expect(found, isNotNull);
      expect(found!.startLine, isNot(block.startLine));
      expect(removePastedBlock(after, found),
          'Edited elsewhere.\nTwo lines now.\n\n$_block1');
    });

    test('null when the block was already removed', () {
      const before = '$_block1\n\n$_block2';
      final block = parsePastedQuestionnaires(before).blocks.first;
      expect(findPastedBlock(_block2, block), isNull);
    });
  });

  group('notesToPlainText', () {
    test('strips tags and decodes common entities', () {
      expect(notesToPlainText('<p>Load in &amp; soundcheck</p><p>Done</p>'),
          'Load in & soundcheck\nDone');
    });
  });
}
