import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';


/// Pre-auth landing screen shown on a fresh launch before the user signs in.
///
/// It exists so the app does not open on a bare login form: a swipeable
/// carousel showcases what Bandmate does using *static, illustrative* mock
/// widgets — no API calls, no real data — and only then offers Log In / Create
/// Account. This both communicates the app's value to a logged-out user and
/// makes clear *why* the real features are account-scoped (private band data),
/// addressing App Review 5.1.1(v).
///
/// Every panel mirrors a feature the mobile app actually has (live session,
/// setlists, invites, contracts, the client payment portal, the dashboard, and
/// bookings). Web-only features (e.g. the Google Calendar sync, which has no
/// mobile UI or API) are intentionally omitted so the showcase never advertises
/// something the iOS app can't do.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _panels = <_DemoPanel>[
    _DemoPanel(
      title: 'Run the night, live',
      caption:
          'Live Session mode keeps the whole band on the same song — see what’s playing and what’s next.',
      preview: _LiveSessionPreview(),
    ),
    _DemoPanel(
      title: 'Build setlists in seconds',
      caption:
          'Arrange songs per set, then push them straight into a live session.',
      preview: _SetlistPreview(),
    ),
    _DemoPanel(
      title: 'Invite your band',
      caption:
          'Add members with an invite code or a quick QR scan — owners and members.',
      preview: _InvitePreview(),
    ),
    _DemoPanel(
      title: 'Send contracts that get signed',
      caption:
          'Send a contract to your client and track it from sent to signed.',
      preview: _ContractPreview(),
    ),
    _DemoPanel(
      title: 'Get paid through the portal',
      caption:
          'Clients pay through the portal — deposits and balances tracked automatically.',
      preview: _PaymentPreview(),
    ),
    _DemoPanel(
      title: 'Your whole season at a glance',
      caption:
          'Every gig, rehearsal, and event for your band on one calendar.',
      preview: _DashboardPreview(),
    ),
    _DemoPanel(
      title: 'Manage every booking',
      caption:
          'Track contracts, payments, and contacts from inquiry to load-out.',
      preview: _BookingsPreview(),
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.music_note,
                  size: 26,
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                ),
                const SizedBox(width: 6),
                Text(
                  'Bandmate',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.systemBlue.resolveFrom(context),
                  ),
                ),
              ],
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _panels.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _panels[i],
              ),
            ),
            _PageDots(count: _panels.length, active: _page),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CupertinoButton.filled(
                    onPressed: () => context.push('/login'),
                    child: const Text('Log In', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(height: 12),
                  CupertinoButton(
                    onPressed: () => context.push('/signup'),
                    child: const Text('Create Account'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

// ── Carousel scaffolding ──────────────────────────────────────────────────────

class _DemoPanel extends StatelessWidget {
  const _DemoPanel({
    required this.title,
    required this.caption,
    required this.preview,
  });

  final String title;
  final String caption;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The preview mocks are fixed-size content inside a Column that
          // wants its natural height. On shorter viewports that natural
          // height may exceed what's available — let this area scroll
          // internally rather than overflow. The minHeight constraint keeps
          // the preview vertically centered when there IS enough room: inside
          // a scroll view height is unbounded, so a bare Center would
          // shrink-wrap and pin the preview to the top.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(child: preview),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: context.primaryText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            style: TextStyle(
              fontSize: 15,
              color: context.secondaryText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive
                ? CupertinoColors.systemBlue.resolveFrom(context)
                : CupertinoColors.systemGrey3.resolveFrom(context),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

/// A phone-screen-like frame the mock previews sit inside, so each panel reads
/// as "a peek at the app" rather than a loose widget.
class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: CupertinoColors.separator.resolveFrom(context),
          width: 0.5,
        ),
      ),
      child: child,
    );
  }
}

// ── Static mock previews (no real data, no network) ──────────────────────────

/// Live Session — mirrors the real "NOW PLAYING" card + "UP NEXT" and queue.
class _LiveSessionPreview extends StatelessWidget {
  const _LiveSessionPreview();

  @override
  Widget build(BuildContext context) {
    return _PreviewFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // NOW PLAYING card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CupertinoColors.systemBlue
                  .resolveFrom(context)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NOW PLAYING',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color:
                            CupertinoColors.systemBlue.resolveFrom(context))),
                const SizedBox(height: 6),
                Text('September',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.primaryText)),
                Text('Earth, Wind & Fire',
                    style: TextStyle(
                        fontSize: 13,
                        color: context.secondaryText)),
                const SizedBox(height: 8),
                // Wrap, not Row: on narrow (zoomed-display) screens the three
                // tags exceed the card width and a Row would overflow.
                const Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MockTag(label: 'Key: A'),
                    _MockTag(label: '126 BPM'),
                    _MockTag(label: '🎤 Mia'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('UP NEXT',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: context.secondaryText)),
          const SizedBox(height: 4),
          Text('Uptown Funk · Bruno Mars',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.primaryText)),
        ],
      ),
    );
  }
}

class _MockTag extends StatelessWidget {
  const _MockTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: context.primaryText)),
    );
  }
}

/// Setlist builder — numbered song list grouped by set.
class _SetlistPreview extends StatelessWidget {
  const _SetlistPreview();

  @override
  Widget build(BuildContext context) {
    const songs = [
      ('1', 'September', 'Earth, Wind & Fire'),
      ('2', 'Uptown Funk', 'Bruno Mars'),
      ('3', "Don't Stop Believin'", 'Journey'),
      ('4', 'I Wanna Dance with Somebody', 'Whitney Houston'),
    ];
    return _PreviewFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set 1 · Reception',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: context.primaryText)),
          const SizedBox(height: 10),
          for (final (trackNumber, title, artist) in songs) ...[
            Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(trackNumber,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.systemBlue
                              .resolveFrom(context))),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.primaryText)),
                      Text(artist,
                          style: TextStyle(
                              fontSize: 11,
                              color: context.secondaryText)),
                    ],
                  ),
                ),
                Icon(CupertinoIcons.line_horizontal_3,
                    size: 15,
                    color: context.tertiaryText),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// Band invites — invite code + QR, role choice.
class _InvitePreview extends StatelessWidget {
  const _InvitePreview();

  @override
  Widget build(BuildContext context) {
    return _PreviewFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invite a Member',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: context.primaryText)),
          const SizedBox(height: 12),
          // Invite code chip + QR glyph
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: CupertinoColors.tertiarySystemBackground
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.ticket,
                          size: 16,
                          color: CupertinoColors.systemBlue
                              .resolveFrom(context)),
                      const SizedBox(width: 8),
                      Text('BAND-7F3K',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: context.primaryText)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemBackground
                      .resolveFrom(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(CupertinoIcons.qrcode,
                    size: 26,
                    color: context.primaryText),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Role segmented look
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemBackground
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: CupertinoColors.systemBackground
                          .resolveFrom(context),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Member',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.primaryText)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text('Owner',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            color: context.secondaryText)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Contracts — sent / awaiting signature status.
class _ContractPreview extends StatelessWidget {
  const _ContractPreview();

  @override
  Widget build(BuildContext context) {
    return _PreviewFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.doc_text,
                  size: 18,
                  color: CupertinoColors.systemBlue.resolveFrom(context)),
              const SizedBox(width: 8),
              Text('Performance Agreement',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: context.primaryText)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Riverfront Wedding · Jun 20',
              style: TextStyle(
                  fontSize: 12,
                  color: context.secondaryText)),
          const SizedBox(height: 14),
          // faux document lines
          for (final w in const [0.9, 0.75, 0.85, 0.6]) ...[
            Container(
              height: 7,
              width: 220 * w,
              decoration: BoxDecoration(
                color: CupertinoColors.tertiarySystemBackground
                    .resolveFrom(context),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(CupertinoIcons.paperplane_fill,
                  size: 13,
                  color: CupertinoColors.systemGreen.resolveFrom(context)),
              const SizedBox(width: 6),
              Text('Sent · awaiting signature',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          CupertinoColors.systemGreen.resolveFrom(context))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Client payment portal — Total / Paid / Balance due + a portal payment.
class _PaymentPreview extends StatelessWidget {
  const _PaymentPreview();

  @override
  Widget build(BuildContext context) {
    return _PreviewFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Riverfront Wedding',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: context.primaryText)),
          const SizedBox(height: 12),
          const _MockAmountRow(
              label: 'Total',
              amount: r'$3,500',
              color: CupertinoColors.label),
          const _MockAmountRow(
              label: 'Paid',
              amount: r'$1,750',
              color: CupertinoColors.systemGreen),
          const _MockAmountRow(
              label: 'Balance due',
              amount: r'$1,750',
              color: CupertinoColors.systemRed),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemBackground
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(CupertinoIcons.creditcard,
                    size: 16,
                    color: CupertinoColors.systemBlue.resolveFrom(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Deposit',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.primaryText)),
                      Text('Client Portal · Jun 2',
                          style: TextStyle(
                              fontSize: 11,
                              color: context.secondaryText)),
                    ],
                  ),
                ),
                Text(r'$1,750',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color:
                            CupertinoColors.systemGreen.resolveFrom(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MockAmountRow extends StatelessWidget {
  const _MockAmountRow({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final String amount;
  final CupertinoDynamicColor color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: context.secondaryText)),
          Text(amount,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: color.resolveFrom(context))),
        ],
      ),
    );
  }
}

/// Dashboard — calendar list of gigs/rehearsals.
class _DashboardPreview extends StatelessWidget {
  const _DashboardPreview();

  @override
  Widget build(BuildContext context) {
    return _PreviewFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('June',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.primaryText)),
          const SizedBox(height: 12),
          const _MockEventRow(
            color: CupertinoColors.systemBlue,
            day: 'FRI 20',
            title: 'Riverfront Wedding',
            subtitle: '7:00 PM · The Boathouse',
          ),
          const SizedBox(height: 10),
          const _MockEventRow(
            color: CupertinoColors.systemOrange,
            day: 'SAT 21',
            title: 'Rehearsal',
            subtitle: '2:00 PM · Studio B',
          ),
          const SizedBox(height: 10),
          const _MockEventRow(
            color: CupertinoColors.systemGreen,
            day: 'SAT 28',
            title: 'Summerfest Main Stage',
            subtitle: '9:30 PM · Downtown',
          ),
        ],
      ),
    );
  }
}

class _MockEventRow extends StatelessWidget {
  const _MockEventRow({
    required this.color,
    required this.day,
    required this.title,
    required this.subtitle,
  });

  final CupertinoDynamicColor color;
  final String day;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 38,
          decoration: BoxDecoration(
            color: color.resolveFrom(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 46,
          child: Text(day,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.secondaryText)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.primaryText)),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 12,
                      color: context.secondaryText)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bookings — list with statuses and amounts.
class _BookingsPreview extends StatelessWidget {
  const _BookingsPreview();

  @override
  Widget build(BuildContext context) {
    return const _PreviewFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MockBookingRow(
            title: 'Riverfront Wedding',
            amount: r'$3,500',
            status: 'Confirmed',
            statusColor: CupertinoColors.systemGreen,
          ),
          SizedBox(height: 10),
          _MockBookingRow(
            title: 'Corporate Gala',
            amount: r'$5,200',
            status: 'Pending',
            statusColor: CupertinoColors.systemOrange,
          ),
          SizedBox(height: 10),
          _MockBookingRow(
            title: 'Summerfest',
            amount: r'$2,000',
            status: 'Draft',
            statusColor: CupertinoColors.systemGrey,
          ),
        ],
      ),
    );
  }
}

class _MockBookingRow extends StatelessWidget {
  const _MockBookingRow({
    required this.title,
    required this.amount,
    required this.status,
    required this.statusColor,
  });

  final String title;
  final String amount;
  final String status;
  final CupertinoDynamicColor statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.primaryText)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor.resolveFrom(context),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(status,
                        style: TextStyle(
                            fontSize: 12,
                            color: context.secondaryText)),
                  ],
                ),
              ],
            ),
          ),
          Text(amount,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.primaryText)),
        ],
      ),
    );
  }
}
