import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../bands/providers/bands_provider.dart';

class PathSelectionScreen extends ConsumerStatefulWidget {
  const PathSelectionScreen({super.key});

  @override
  ConsumerState<PathSelectionScreen> createState() =>
      _PathSelectionScreenState();
}

class _PathSelectionScreenState extends ConsumerState<PathSelectionScreen> {
  bool _soloLoading = false;
  String? _soloError;

  Future<void> _goSolo() async {
    setState(() {
      _soloLoading = true;
      _soloError = null;
    });
    try {
      await ref.read(bandsProvider.notifier).goSolo();
      // Router guard detects band now exists and navigates to dashboard.
    } catch (e) {
      setState(() => _soloError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _soloLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: const Text('Get Started'),
          automaticallyImplyLeading: false,
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () async =>
                ref.read(authProvider.notifier).logout(),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.square_arrow_right, size: 18),
                SizedBox(width: 4),
                Text('Sign out'),
              ],
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'How would you like to use Bandmate?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You can always add or join a band later from Settings.',
                  style: TextStyle(
                    fontSize: 14,
                    color:
                        CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 32),
                _PathCard(
                  icon: CupertinoIcons.music_mic,
                  title: 'Create a Band',
                  subtitle: 'Start a new band and invite your members.',
                  onTap: () => context.push('/bands/create'),
                ),
                const SizedBox(height: 16),
                _PathCard(
                  icon: CupertinoIcons.link,
                  title: 'Join a Band',
                  subtitle:
                      'Enter an invite code, scan a QR, or use an email link.',
                  onTap: () => context.push('/bands/join'),
                ),
                const SizedBox(height: 16),
                _PathCard(
                  icon: CupertinoIcons.music_note,
                  title: 'Go Solo',
                  subtitle:
                      'Use Bandmate for personal gig tracking and setlists.',
                  onTap: _soloLoading ? null : _goSolo,
                  loading: _soloLoading,
                ),
                if (_soloError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _soloError!,
                    style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.systemRed.resolveFrom(context)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: CupertinoColors.systemBlue
                    .resolveFrom(context)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: loading
                    ? const CupertinoActivityIndicator()
                    : Icon(icon,
                        color: CupertinoColors.systemBlue.resolveFrom(context),
                        size: 24),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context))),
                ],
              ),
            ),
            Icon(CupertinoIcons.chevron_right,
                size: 18,
                color: CupertinoColors.tertiaryLabel.resolveFrom(context)),
          ],
        ),
      ),
    );
  }
}
