import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../../events/data/models/event_summary.dart';
import '../../../shared/utils/time_format.dart';

/// A high-prominence banner shown on the dashboard when an event is currently
/// in progress. Tapping navigates to the event detail screen.
class LiveNowCard extends StatefulWidget {
  const LiveNowCard({
    super.key,
    required this.event,
    required this.onTap,
  });

  final EventSummary event;
  final VoidCallback onTap;

  @override
  State<LiveNowCard> createState() => _LiveNowCardState();
}

class _LiveNowCardState extends State<LiveNowCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    // Accent colour — a slightly muted red so it doesn't scream too loudly.
    final accentColor = CupertinoColors.systemRed.resolveFrom(context);
    final cardBg = isDark
        ? accentColor.withValues(alpha: 0.18)
        : accentColor.withValues(alpha: 0.07);
    final borderColor = accentColor.withValues(alpha: isDark ? 0.45 : 0.30);

    return Semantics(
      button: true,
      label: 'Live now: ${widget.event.title}. Tap to open event.',
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header row ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    _PulsingDot(animation: _pulseAnimation, color: accentColor),
                    const SizedBox(width: 7),
                    Text(
                      'Live Now',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: accentColor,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 14,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ],
                ),
              ),

              // ── Divider ────────────────────────────────────────────────────
              Container(
                height: 0.5,
                color: borderColor,
              ),

              // ── Event info ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Icon column — mirrors EventCard's left column style.
                    _EventIcon(event: widget.event),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.event.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.label.resolveFrom(context),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _subtitle {
    final event = widget.event;
    final parts = <String>[];

    // Date + time line.
    final dateStr = DateFormat('EEEE, MMMM d').format(event.parsedDate);
    if (event.time != null && event.time!.isNotEmpty) {
      parts.add('$dateStr at ${toAmPm(event.time!)}');
    } else {
      parts.add(dateStr);
    }

    // Venue on same line when short enough, otherwise it'll ellipsis.
    if (event.venueName != null && event.venueName!.isNotEmpty) {
      parts.add(event.venueName!);
    }

    return parts.join('  ·  ');
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _PulsingDot extends StatelessWidget {
  const _PulsingDot({required this.animation, required this.color});

  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) => CustomPaint(
        size: const Size(10, 10),
        painter: _DotPainter(
          innerColor: color,
          outerColor: color.withValues(alpha: animation.value * 0.35),
          // Outer ring grows as inner opacity fades, creating a "ripple" feel.
          outerRadius: 5.0 + (1.0 - animation.value) * 3.0,
        ),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  const _DotPainter({
    required this.innerColor,
    required this.outerColor,
    required this.outerRadius,
  });

  final Color innerColor;
  final Color outerColor;
  final double outerRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Outer ripple ring.
    canvas.drawCircle(
      center,
      math.min(outerRadius, size.width / 2),
      Paint()..color = outerColor,
    );
    // Solid inner dot.
    canvas.drawCircle(center, 4.0, Paint()..color = innerColor);
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.innerColor != innerColor ||
      old.outerColor != outerColor ||
      old.outerRadius != outerRadius;
}

class _EventIcon extends StatelessWidget {
  const _EventIcon({required this.event});

  final EventSummary event;

  @override
  Widget build(BuildContext context) {
    final iconPath = event.gigIconPath;
    if (iconPath != null) {
      return Image.asset(iconPath, width: 44, height: 44, fit: BoxFit.contain);
    }
    // Rehearsal or unknown type — use a mic icon in a tinted circle.
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: CupertinoColors.systemBlue
            .resolveFrom(context)
            .withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        CupertinoIcons.music_mic,
        size: 22,
        color: CupertinoColors.systemBlue.resolveFrom(context),
      ),
    );
  }
}
