import 'package:flutter/cupertino.dart';
import '../data/models/event_setlist.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';

/// Shared visual language for client must-play / do-not-play markers, used by
/// the catalog list, setlist rows, and the song picker so a flagged song looks
/// the same everywhere.

/// Accent used for the must-play star and caption.
Color clientMustPlayColor(BuildContext context) =>
    CupertinoColors.systemOrange.resolveFrom(context);

/// Applies the do-not-play treatment (strikethrough + dimmed) to [base], or
/// returns it unchanged for other statuses.
TextStyle clientRequestTextStyle(
  BuildContext context,
  ClientSongStatus status,
  TextStyle base,
) {
  if (status != ClientSongStatus.doNotPlay) return base;
  return base.copyWith(
    decoration: TextDecoration.lineThrough,
    decorationColor: context.secondaryText,
    color: context.tertiaryText,
  );
}

/// Filled star shown beside a must-play song title.
class ClientRequestStar extends StatelessWidget {
  const ClientRequestStar({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) => Icon(
        CupertinoIcons.star_fill,
        size: size,
        color: clientMustPlayColor(context),
        semanticLabel: 'Must play',
      );
}

/// Small caption under a song: "Must play" or "Do not play".
class ClientRequestCaption extends StatelessWidget {
  const ClientRequestCaption(this.status, {super.key});

  final ClientSongStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ClientSongStatus.mustPlay:
        return Text(
          'Must play',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: clientMustPlayColor(context),
          ),
        );
      case ClientSongStatus.doNotPlay:
        return Text(
          'Do not play',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.systemRed.resolveFrom(context),
          ),
        );
      case ClientSongStatus.none:
        return const SizedBox.shrink();
    }
  }
}
