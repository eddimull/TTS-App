import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/shared/providers/selected_band_provider.dart';
import 'package:tts_bandmate/shared/utils/maps_launch.dart';
import 'package:tts_bandmate/shared/widgets/attachment_widgets.dart';
import 'package:tts_bandmate/shared/widgets/auth_thumbnail.dart';
import 'package:tts_bandmate/shared/widgets/error_view.dart';
import '../data/lodging_repository.dart';
import '../data/models/lodging.dart';
import '../providers/lodging_provider.dart';

class LodgingDetailScreen extends ConsumerWidget {
  const LodgingDetailScreen({super.key, required this.lodgingId});
  final int lodgingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lodgingDetailProvider(lodgingId));

    return async.when(
      loading: () => const CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(),
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(),
        child: ErrorView(
          message: ErrorView.friendlyMessage(e),
          onRetry: () => ref.invalidate(lodgingDetailProvider(lodgingId)),
        ),
      ),
      data: (state) => _LodgingDetailView(
        lodgingId: lodgingId,
        lodging: state.lodging,
        canWrite: state.canWrite,
      ),
    );
  }
}

class _LodgingDetailView extends ConsumerWidget {
  const _LodgingDetailView({
    required this.lodgingId,
    required this.lodging,
    required this.canWrite,
  });

  final int lodgingId;
  final Lodging lodging;
  final bool canWrite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = DateFormat('EEEE, MMMM d, yyyy');
    final timeFmt = DateFormat('h:mm a');

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(lodging.name),
        trailing: canWrite
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => context.push('/lodging/$lodgingId/edit'),
                child: const Text('Edit'),
              )
            : null,
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            child: Column(
              children: [
                _DateRow(
                  label: 'Check-in',
                  value:
                      '${dateFmt.format(lodging.parsedCheckIn)} · ${timeFmt.format(lodging.parsedCheckIn)}',
                ),
                Container(
                  height: 0.5,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: CupertinoColors.separator.resolveFrom(context),
                ),
                _DateRow(
                  label: 'Check-out',
                  value:
                      '${dateFmt.format(lodging.parsedCheckOut)} · ${timeFmt.format(lodging.parsedCheckOut)}',
                ),
              ],
            ),
          ),

          if (lodging.address != null && lodging.address!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Card(
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => openInMaps(
                  lat: lodging.latitude,
                  lng: lodging.longitude,
                  address: lodging.address,
                  name: lodging.name,
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.location,
                        size: 20, color: context.secondaryText),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        lodging.address!,
                        style: TextStyle(
                            fontSize: 15, color: context.primaryText),
                      ),
                    ),
                    Icon(CupertinoIcons.map,
                        size: 18, color: CupertinoColors.systemBlue.resolveFrom(context)),
                  ],
                ),
              ),
            ),
          ],

          if (lodging.rooms.isNotEmpty) ...[
            const SizedBox(height: 12),
            const _SectionLabel('Rooms'),
            const SizedBox(height: 8),
            _Card(
              child: Column(
                children: [
                  for (int i = 0; i < lodging.rooms.length; i++) ...[
                    if (i > 0)
                      Container(
                        height: 0.5,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        color: CupertinoColors.separator.resolveFrom(context),
                      ),
                    _RoomRow(room: lodging.rooms[i]),
                  ],
                ],
              ),
            ),
          ],

          if (lodging.notes != null && lodging.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const _SectionLabel('Notes'),
            const SizedBox(height: 8),
            _Card(
              child: Text(
                lodging.notes!,
                style: TextStyle(fontSize: 15, color: context.primaryText),
              ),
            ),
          ],

          const SizedBox(height: 12),
          const _SectionLabel('Attachments'),
          const SizedBox(height: 8),
          _AttachmentsSection(
            lodgingId: lodgingId,
            attachments: lodging.attachments,
            canWrite: canWrite,
          ),

          if (lodging.booking != null || lodging.event != null) ...[
            const SizedBox(height: 12),
            const _SectionLabel('Linked to'),
            const SizedBox(height: 8),
            if (lodging.booking != null)
              _LinkRow(
                icon: CupertinoIcons.book,
                title: lodging.booking!.name,
                onTap: () {
                  final bandId = ref.read(selectedBandProvider).value;
                  if (bandId == null) return;
                  context.push('/bookings/$bandId/${lodging.booking!.id}');
                },
              ),
            // The backend event-link payload carries only a numeric `id`, but
            // the event-detail route is keyed by the event's string `key` —
            // we don't have that here, so the event is shown as plain text
            // rather than a broken/incorrect link.
            if (lodging.event != null) ...[
              if (lodging.booking != null) const SizedBox(height: 8),
              _LinkRow(
                icon: CupertinoIcons.calendar,
                title: lodging.event!.title,
                onTap: null,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(CupertinoIcons.calendar, size: 20, color: context.secondaryText),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: context.secondaryText),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(fontSize: 15, color: context.primaryText),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.room});
  final LodgingRoom room;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          room.label,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: context.primaryText),
        ),
        if (room.confirmationNumber != null &&
            room.confirmationNumber!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            'conf# ${room.confirmationNumber}',
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: context.secondaryText,
            ),
          ),
        ],
        if (room.notes != null && room.notes!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            room.notes!,
            style: TextStyle(fontSize: 12, color: context.tertiaryText),
          ),
        ],
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.title, this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Icon(icon, size: 20, color: context.secondaryText),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(fontSize: 15, color: context.primaryText),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onTap != null)
          Icon(CupertinoIcons.chevron_right,
              size: 16, color: context.tertiaryText),
      ],
    );

    return _Card(
      child: onTap != null
          ? CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: onTap,
              child: row,
            )
          : row,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.secondaryText,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

// ── Attachments ───────────────────────────────────────────────────────────────

class _AttachmentsSection extends ConsumerStatefulWidget {
  const _AttachmentsSection({
    required this.lodgingId,
    required this.attachments,
    required this.canWrite,
  });

  final int lodgingId;
  final List<LodgingAttachment> attachments;
  final bool canWrite;

  @override
  ConsumerState<_AttachmentsSection> createState() =>
      _AttachmentsSectionState();
}

class _AttachmentsSectionState extends ConsumerState<_AttachmentsSection> {
  bool _uploading = false;

  Future<void> _addPhotos() async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 100);
    if (picked.isEmpty || !mounted) return;

    final bandId = ref.read(selectedBandProvider).value;
    if (bandId == null) return;

    setState(() => _uploading = true);
    try {
      final repo = ref.read(lodgingRepositoryProvider);
      for (final x in picked) {
        final bytes = await x.readAsBytes();
        await repo.uploadAttachment(
          bandId,
          widget.lodgingId,
          bytes: bytes,
          filename: x.name,
        );
      }
      ref.invalidate(lodgingDetailProvider(widget.lodgingId));
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Upload Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deleteAttachment(LodgingAttachment attachment) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('Delete Attachment'),
        content: Text('Remove "${attachment.filename}"?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final bandId = ref.read(selectedBandProvider).value;
    if (bandId == null) return;

    try {
      await ref
          .read(lodgingRepositoryProvider)
          .deleteAttachment(bandId, widget.lodgingId, attachment.id);
      ref.invalidate(lodgingDetailProvider(widget.lodgingId));
    } catch (e) {
      if (mounted) {
        showCupertinoDialog<void>(
          context: context,
          builder: (dialogContext) => CupertinoAlertDialog(
            title: const Text('Delete Failed'),
            content: Text(e.toString()),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageAttachments = widget.attachments
        .where((a) => a.mimeType.startsWith('image/'))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.attachments.isNotEmpty)
          _Card(
            child: Column(
              children: [
                for (int i = 0; i < widget.attachments.length; i++) ...[
                  if (i > 0)
                    Container(
                      height: 0.5,
                      color: CupertinoColors.separator.resolveFrom(context),
                    ),
                  _AttachmentRow(
                    attachment: widget.attachments[i],
                    imageAttachments: imageAttachments,
                    canWrite: widget.canWrite,
                    onDelete: () => _deleteAttachment(widget.attachments[i]),
                  ),
                ],
              ],
            ),
          )
        else
          Text(
            'No attachments yet.',
            style: TextStyle(fontSize: 13, color: context.secondaryText),
          ),
        if (widget.canWrite) ...[
          const SizedBox(height: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: _uploading ? null : _addPhotos,
            child: _uploading
                ? const CupertinoActivityIndicator()
                : const Text('Add photo'),
          ),
        ],
      ],
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.imageAttachments,
    required this.canWrite,
    required this.onDelete,
  });

  final LodgingAttachment attachment;
  final List<LodgingAttachment> imageAttachments;
  final bool canWrite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isImage = attachment.mimeType.startsWith('image/');
    final resolvedUrl = resolveAttachmentUrl(attachment.url);

    return GestureDetector(
      onLongPress: canWrite ? onDelete : null,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: () => _handleTap(context, isImage, resolvedUrl),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
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
                child: Text(
                  attachment.filename,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w400),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canWrite)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: onDelete,
                  child: const Icon(CupertinoIcons.delete,
                      size: 18, color: CupertinoColors.destructiveRed),
                )
              else
                Icon(CupertinoIcons.chevron_right,
                    size: 16, color: context.tertiaryText),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(BuildContext context, bool isImage, String resolvedUrl) {
    if (isImage && imageAttachments.isNotEmpty) {
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
