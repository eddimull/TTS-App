// Parsing for questionnaire answers the server pastes into `events.notes`
// (`QuestionnaireMappingService::buildNotesBlock`). A pasted block looks like:
//
//     ----------
//     Customer submitted "Wedding Day Questionnaire" on Oct 20
//     == Bride and Groom Information ==
//     Bride / Groom: Grace Terreson
//     ...

// One `== Label ==` group inside a pasted block.
class PastedSection {
  const PastedSection({required this.label, required this.lines});

  /// Section name; "Answers" for lines that sit before any `== ==` header.
  final String label;

  /// Non-blank answer lines, in order.
  final List<String> lines;
}

/// A pasted questionnaire block.
class PastedQuestionnaire {
  const PastedQuestionnaire({
    required this.name,
    required this.date,
    required this.sections,
    required this.startLine,
    required this.endLine,
  });

  /// Questionnaire name from the `Customer submitted "<name>"` line.
  final String name;

  /// Free-text date after `on`, as written by the server.
  final String date;
  final List<PastedSection> sections;

  /// Line range of the whole block (header included) in the notes text,
  /// `endLine` exclusive. Used to remove the block.
  final int startLine;
  final int endLine;

  /// Number of answers: lines that look like `Label: value`, falling back to
  /// every non-blank line when the block has none.
  int get answerCount {
    var labelled = 0;
    var all = 0;
    for (final s in sections) {
      for (final l in s.lines) {
        all++;
        if (_answerRe.hasMatch(l)) labelled++;
      }
    }
    return labelled > 0 ? labelled : all;
  }
}

final _dashRe = RegExp(r'^-{10,}$');
final _submittedRe = RegExp(r'^Customer submitted "(.*)" on (.*)$');
final _sectionRe = RegExp(r'^==\s*(.*?)\s*==$');
final _answerRe = RegExp(r'^[^:]+:\s*\S');

bool _isBlockStart(List<String> lines, int i) =>
    i + 1 < lines.length &&
    _dashRe.hasMatch(lines[i].trim()) &&
    _submittedRe.hasMatch(lines[i + 1].trim());

/// Splits plain-text [notes] into the band's own notes and any pasted
/// questionnaire blocks. A block runs from its `----------` line to the next
/// block header, or the end of the notes.
({String bandNotes, List<PastedQuestionnaire> blocks})
    parsePastedQuestionnaires(String notes) {
  final lines = notes.replaceAll('\r\n', '\n').split('\n');
  final blocks = <PastedQuestionnaire>[];

  var i = 0;
  while (i < lines.length) {
    if (!_isBlockStart(lines, i)) {
      i++;
      continue;
    }
    final start = i;
    final m = _submittedRe.firstMatch(lines[i + 1].trim())!;
    var end = i + 2;
    while (end < lines.length && !_isBlockStart(lines, end)) {
      end++;
    }

    final sections = <PastedSection>[];
    var label = 'Answers';
    var current = <String>[];
    var sawHeader = false;
    void flush() {
      if (current.isNotEmpty || (sawHeader && label != 'Answers')) {
        sections.add(PastedSection(label: label, lines: current));
      }
    }

    for (var j = start + 2; j < end; j++) {
      final line = lines[j].trim();
      final h = _sectionRe.firstMatch(line);
      if (h != null) {
        flush();
        label = h.group(1)!;
        sawHeader = true;
        current = <String>[];
      } else if (line.isNotEmpty) {
        current.add(line);
      }
    }
    flush();

    blocks.add(PastedQuestionnaire(
      name: m.group(1)!.trim(),
      date: m.group(2)!.trim(),
      sections: sections,
      startLine: start,
      endLine: end,
    ));
    i = end;
  }

  return (
    bandNotes: _joinKept(lines, blocks),
    blocks: blocks,
  );
}

/// Notes with [block] removed. [notes] must be the same text [block] was
/// parsed from.
String removePastedBlock(String notes, PastedQuestionnaire block) {
  final lines = notes.replaceAll('\r\n', '\n').split('\n');
  return _joinKept(lines, [block]);
}

/// Lines outside [removed] blocks. Text on either side of a removed block is
/// joined by one blank line; everything else is left as written.
String _joinKept(List<String> lines, List<PastedQuestionnaire> removed) {
  if (removed.isEmpty) return lines.join('\n').trim();

  final segments = <List<String>>[];
  var cursor = 0;
  for (final b in removed) {
    segments.add(lines.sublist(cursor, b.startLine));
    cursor = b.endLine;
  }
  segments.add(lines.sublist(cursor));

  final parts = <String>[];
  for (final seg in segments) {
    final text = seg.join('\n').trim();
    if (text.isNotEmpty) parts.add(text);
  }
  return parts.join('\n\n');
}

/// Event notes arrive as HTML from the server; this is the plain text the
/// edit screen and the Notes tab work with.
String notesToPlainText(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>'), '\n')
    .replaceAll(RegExp(r'<p[^>]*>'), '')
    .replaceAll('</p>', '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .trim();
