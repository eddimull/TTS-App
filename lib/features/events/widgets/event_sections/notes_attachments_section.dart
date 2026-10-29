import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/widgets/event_sections/section_primitives.dart';
import 'package:tts_bandmate/shared/widgets/attachment_widgets.dart';
import 'package:tts_bandmate/shared/widgets/auth_thumbnail.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Notes + Attachments (combined section) ────────────────────────────────────

/// Bundles the free-text notes and band-internal file attachments into a
/// single "Notes" section. Long notes are clamped to 6 lines with a
/// "Show more"/"Show less" toggle, and attachments beyond the first 3 are
/// hidden behind a "Show all (N)" toggle. Both toggles are local state so
/// expanding one doesn't affect the other.
class NotesAndAttachmentsSection extends StatefulWidget {
  const NotesAndAttachmentsSection({
    super.key,
    this.notesHtml,
    this.attachments = const [],
  });

  final String? notesHtml;
  final List<EventAttachment> attachments;

  static const int _attachmentPreviewCount = 3;
  static const int _notesClampLines = 6;

  static bool hasContent(
          String? notesHtml, List<EventAttachment> attachments) =>
      (notesHtml != null && notesHtml.isNotEmpty) || attachments.isNotEmpty;

  @override
  State<NotesAndAttachmentsSection> createState() =>
      _NotesAndAttachmentsSectionState();
}

class _NotesAndAttachmentsSectionState
    extends State<NotesAndAttachmentsSection> {
  bool _notesExpanded = false;
  bool _attachmentsExpanded = false;

  String get _plainNotes {
    final html = widget.notesHtml ?? '';
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<p[^>]*>'), '')
        .replaceAll('</p>', '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  /// Cheap heuristic for "would this overflow 6 lines" without a
  /// LayoutBuilder/TextPainter measure pass: count explicit newlines plus
  /// an estimate of wrapped lines from character count.
  bool get _notesOverflow {
    final notes = _plainNotes;
    if (notes.isEmpty) return false;
    final estimatedLines = '\n'.allMatches(notes).length + notes.length ~/ 40;
    return estimatedLines > NotesAndAttachmentsSection._notesClampLines;
  }

  @override
  Widget build(BuildContext context) {
    final notes = _plainNotes;
    final hasNotes = notes.isNotEmpty;
    final attachments = widget.attachments;
    final hasAttachments = attachments.isNotEmpty;
    final showNotesToggle = hasNotes && _notesOverflow;
    final visibleAttachments = _attachmentsExpanded
        ? attachments
        : attachments
            .take(NotesAndAttachmentsSection._attachmentPreviewCount)
            .toList();
    final showAttachmentsToggle =
        attachments.length > NotesAndAttachmentsSection._attachmentPreviewCount;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasNotes) ...[
            Text(
              notes,
              style: const TextStyle(fontSize: 15),
              maxLines: _notesExpanded
                  ? null
                  : NotesAndAttachmentsSection._notesClampLines,
              overflow: _notesExpanded ? null : TextOverflow.ellipsis,
            ),
            if (showNotesToggle)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () =>
                      setState(() => _notesExpanded = !_notesExpanded),
                  child: Text(_notesExpanded ? 'Show less' : 'Show more'),
                ),
              ),
          ],
          if (hasNotes && hasAttachments)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SectionDivider(),
            ),
          if (hasAttachments) ...[
            for (int i = 0; i < visibleAttachments.length; i++) ...[
              if (i > 0) const SectionDivider(),
              AttachmentRow(
                attachment: visibleAttachments[i],
                imageAttachments: attachments
                    .where((a) => a.mimeType.startsWith('image/'))
                    .toList(),
              ),
            ],
            if (showAttachmentsToggle && !_attachmentsExpanded)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => setState(() => _attachmentsExpanded = true),
                  child: Text('Show all (${attachments.length})'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Attachments ───────────────────────────────────────────────────────────────
// (Rendered inline inside NotesAndAttachmentsSection above — no standalone
// card wrapper needed since both live in the same "Notes" section card.)

class AttachmentRow extends StatelessWidget {
  const AttachmentRow({
    super.key,
    required this.attachment,
    required this.imageAttachments,
  });
  final EventAttachment attachment;

  /// All image attachments in the parent list — used to resolve the lightbox
  /// start index when this row is an image.
  final List<EventAttachment> imageAttachments;

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.mimeType.startsWith('image/');
    final resolvedUrl = resolveAttachmentUrl(attachment.url);

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => _handleTap(context, isImage, resolvedUrl),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // Thumbnail for images, icon for everything else
            SizedBox(
              width: 40,
              height: 40,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: isImage && resolvedUrl.isNotEmpty
                    ? AuthThumbnail(url: resolvedUrl)
                    : ColoredBox(
                        color: CupertinoColors.systemBlue
                            .resolveFrom(context)
                            .withValues(alpha: 0.12),
                        child: Center(
                          child: Icon(
                            attachmentIcon(attachment.mimeType),
                            size: 22,
                            color:
                                CupertinoColors.systemBlue.resolveFrom(context),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.filename,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    attachment.formattedSize,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: context.tertiaryText,
            ),
          ],
        ),
      ),
    );
  }

  void _handleTap(BuildContext context, bool isImage, String resolvedUrl) {
    if (isImage && imageAttachments.isNotEmpty) {
      // Find this attachment's index within the image-only list.
      final startIndex =
          imageAttachments.indexWhere((a) => a.id == attachment.id);
      Navigator.of(context).push(
        CupertinoPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => AttachmentLightbox(
            attachments: imageAttachments,
            startIndex: startIndex < 0 ? 0 : startIndex,
          ),
        ),
      );
    } else {
      if (resolvedUrl.isEmpty) return;
      final uri = Uri.tryParse(resolvedUrl);
      if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
