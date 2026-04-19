import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/bands_provider.dart';

class JoinBandScreen extends ConsumerStatefulWidget {
  const JoinBandScreen({super.key});

  @override
  ConsumerState<JoinBandScreen> createState() => _JoinBandScreenState();
}

class _JoinBandScreenState extends ConsumerState<JoinBandScreen> {
  final _codeController = TextEditingController();
  bool _scanning = false;
  bool _isSubmitting = false;
  String? _codeError;
  String? _submitError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _joinWithKey(String key) async {
    if (key.trim().isEmpty) {
      setState(() => _codeError = 'Please enter an invite code.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _codeError = null;
      _submitError = null;
    });
    try {
      await ref.read(bandsProvider.notifier).joinBand(key.trim());
      // Router guard detects band and navigates to dashboard.
    } catch (e) {
      if (mounted) setState(() => _submitError = 'Invalid or expired code. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar:
          const CupertinoNavigationBar(middle: Text('Join a Band')),
      child: SafeArea(
        child: _scanning
            ? _buildScanner(context)
            : _buildCodeEntry(context),
      ),
    );
  }

  Widget _buildCodeEntry(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Enter an invite code',
              style:
                  TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
              'Ask a band owner for their code, or scan their QR code below.',
              style: TextStyle(
                  fontSize: 14,
                  color:
                      CupertinoColors.secondaryLabel.resolveFrom(context))),
          const SizedBox(height: 24),
          CupertinoTextField(
            controller: _codeController,
            placeholder: 'Invite code',
            textInputAction: TextInputAction.done,
            autocorrect: false,
            onSubmitted: (_) => _joinWithKey(_codeController.text),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: CupertinoColors.tertiarySystemBackground
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(10),
              border: _codeError != null
                  ? Border.all(
                      color: CupertinoColors.systemRed.resolveFrom(context))
                  : null,
            ),
          ),
          if (_codeError != null) ...[
            const SizedBox(height: 4),
            Text(_codeError!,
                style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemRed.resolveFrom(context))),
          ],
          const SizedBox(height: 16),
          CupertinoButton.filled(
            onPressed: _isSubmitting
                ? null
                : () => _joinWithKey(_codeController.text),
            child: _isSubmitting
                ? const CupertinoActivityIndicator(
                    color: CupertinoColors.white)
                : const Text('Join'),
          ),
          const SizedBox(height: 24),
          CupertinoButton(
            onPressed: () => setState(() => _scanning = true),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.qrcode_viewfinder,
                    color: CupertinoColors.systemBlue.resolveFrom(context)),
                const SizedBox(width: 8),
                const Text('Scan QR Code'),
              ],
            ),
          ),
          if (_submitError != null) ...[
            const SizedBox(height: 12),
            Text(_submitError!,
                style: TextStyle(
                    fontSize: 13,
                    color: CupertinoColors.systemRed.resolveFrom(context)),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Widget _buildScanner(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            final code = capture.barcodes.firstOrNull?.rawValue;
            if (code != null && code.isNotEmpty) {
              setState(() => _scanning = false);
              _joinWithKey(code);
            }
          },
        ),
        Positioned(
          top: 16,
          left: 16,
          child: CupertinoButton(
            color: CupertinoColors.black.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            borderRadius: BorderRadius.circular(20),
            onPressed: () => setState(() => _scanning = false),
            child: const Text('Cancel',
                style: TextStyle(color: CupertinoColors.white)),
          ),
        ),
      ],
    );
  }
}
