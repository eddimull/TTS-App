import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

/// Pre-auth landing screen shown on a fresh launch before the user signs in.
///
/// It exists so the app does not open on a bare login form: a swipeable
/// carousel showcases what Bandmate does (dashboard, bookings, library,
/// finances) using *static, illustrative* mock widgets — no API calls, no real
/// data — and only then offers Log In / Create Account. This both communicates
/// the app's value to a logged-out user and makes clear *why* the real features
/// are account-scoped (private band data), addressing App Review 5.1.1(v).
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
      title: 'Your whole season at a glance',
      caption:
          'See every gig, rehearsal, and event for your band on one calendar.',
      preview: _DashboardPreview(),
    ),
    _DemoPanel(
      title: 'Manage every booking',
      caption:
          'Track contracts, payments, and contacts from inquiry to load-out.',
      preview: _BookingsPreview(),
    ),
    _DemoPanel(
      title: 'Charts & setlists in your pocket',
      caption:
          'Build setlists and keep the whole band on the same chart, live.',
      preview: _LibraryPreview(),
    ),
    _DemoPanel(
      title: 'Know where the money goes',
      caption:
          'See payouts per member and what each gig brought in — automatically.',
      preview: _FinancesPreview(),
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
          Expanded(child: Center(child: preview)),
          const SizedBox(height: 24),
          Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: CupertinoColors.label.resolveFrom(context),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            style: TextStyle(
              fontSize: 15,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
                  color: CupertinoColors.label.resolveFrom(context))),
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
                  color: CupertinoColors.secondaryLabel.resolveFrom(context))),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context))),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 12,
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context))),
            ],
          ),
        ),
      ],
    );
  }
}

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
            status: 'Deposit due',
            statusColor: CupertinoColors.systemOrange,
          ),
          SizedBox(height: 10),
          _MockBookingRow(
            title: 'Summerfest',
            amount: r'$2,000',
            status: 'Inquiry',
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
                        color: CupertinoColors.label.resolveFrom(context))),
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
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context))),
                  ],
                ),
              ],
            ),
          ),
          Text(amount,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: CupertinoColors.label.resolveFrom(context))),
        ],
      ),
    );
  }
}

class _LibraryPreview extends StatelessWidget {
  const _LibraryPreview();

  @override
  Widget build(BuildContext context) {
    const songs = [
      ('1', 'September', 'Earth, Wind & Fire'),
      ('2', "Don't Stop Believin'", 'Journey'),
      ('3', 'Uptown Funk', 'Bruno Mars'),
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
                  color: CupertinoColors.label.resolveFrom(context))),
          const SizedBox(height: 10),
          for (final (num, title, artist) in songs) ...[
            Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(num,
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
                              color:
                                  CupertinoColors.label.resolveFrom(context))),
                      Text(artist,
                          style: TextStyle(
                              fontSize: 11,
                              color: CupertinoColors.secondaryLabel
                                  .resolveFrom(context))),
                    ],
                  ),
                ),
                Icon(CupertinoIcons.music_note,
                    size: 14,
                    color:
                        CupertinoColors.tertiaryLabel.resolveFrom(context)),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _FinancesPreview extends StatelessWidget {
  const _FinancesPreview();

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
                  color: CupertinoColors.label.resolveFrom(context))),
          const SizedBox(height: 2),
          Text(r'$3,500 total payout',
              style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context))),
          const SizedBox(height: 14),
          const _MockPayoutRow(name: 'Vocals', amount: r'$700'),
          const _MockPayoutRow(name: 'Guitar', amount: r'$700'),
          const _MockPayoutRow(name: 'Bass', amount: r'$700'),
          const _MockPayoutRow(name: 'Keys', amount: r'$700'),
          const _MockPayoutRow(name: 'Drums', amount: r'$700'),
        ],
      ),
    );
  }
}

class _MockPayoutRow extends StatelessWidget {
  const _MockPayoutRow({required this.name, required this.amount});

  final String name;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name,
              style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.label.resolveFrom(context))),
          Text(amount,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: CupertinoColors.label.resolveFrom(context))),
        ],
      ),
    );
  }
}
