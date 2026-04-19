import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/bands_provider.dart';

class CreateBandScreen extends ConsumerStatefulWidget {
  const CreateBandScreen({super.key});

  @override
  ConsumerState<CreateBandScreen> createState() => _CreateBandScreenState();
}

class _CreateBandScreenState extends ConsumerState<CreateBandScreen> {
  // Step 1: name
  final _nameController = TextEditingController();
  String? _nameError;

  // Step 2: invite
  final _emailController = TextEditingController();
  final List<String> _emails = [];
  String? _emailError;

  int _step = 1; // 1 = name, 2 = invite
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _addEmail() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      setState(() => _emailError = 'Enter a valid email address.');
      return;
    }
    if (_emails.contains(email)) {
      setState(() => _emailError = 'Already added.');
      return;
    }
    setState(() {
      _emails.add(email);
      _emailError = null;
    });
    _emailController.clear();
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _nameError = 'Please enter a band name.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      await ref
          .read(bandsProvider.notifier)
          .createBand(_nameController.text.trim(), _emails);
      // Router guard sees new band and navigates to dashboard.
    } catch (e) {
      if (mounted) setState(() => _submitError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(_step == 1 ? 'Name Your Band' : 'Invite Members'),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _step == 1 ? _buildStep1(context) : _buildStep2(context),
        ),
      ),
    );
  }

  Widget _buildStep1(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('What\'s your band called?',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        CupertinoTextField(
          controller: _nameController,
          placeholder: 'Band Name',
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _goToStep2(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(10),
            border: _nameError != null
                ? Border.all(color: CupertinoColors.systemRed.resolveFrom(context))
                : null,
          ),
        ),
        if (_nameError != null) ...[
          const SizedBox(height: 4),
          Text(_nameError!,
              style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemRed.resolveFrom(context))),
        ],
        const Spacer(),
        CupertinoButton.filled(
          onPressed: _goToStep2,
          child: const Text('Next'),
        ),
      ],
    );
  }

  void _goToStep2() {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _nameError = 'Please enter a band name.');
      return;
    }
    setState(() {
      _nameError = null;
      _step = 2;
    });
  }

  Widget _buildStep2(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Invite your bandmates',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('They\'ll receive an email invitation.',
            style: TextStyle(
                fontSize: 14,
                color: CupertinoColors.secondaryLabel.resolveFrom(context))),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _emailController,
                placeholder: 'Email address',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addEmail(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: CupertinoColors.tertiarySystemBackground
                      .resolveFrom(context),
                  borderRadius: BorderRadius.circular(10),
                  border: _emailError != null
                      ? Border.all(
                          color:
                              CupertinoColors.systemRed.resolveFrom(context))
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            CupertinoButton(
              onPressed: _addEmail,
              padding: EdgeInsets.zero,
              child: Icon(CupertinoIcons.add_circled_solid,
                  size: 36,
                  color: CupertinoColors.systemBlue.resolveFrom(context)),
            ),
          ],
        ),
        if (_emailError != null) ...[
          const SizedBox(height: 4),
          Text(_emailError!,
              style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemRed.resolveFrom(context))),
        ],
        if (_emails.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _emails
                .map((email) => _EmailChip(
                      email: email,
                      onRemove: () => setState(() => _emails.remove(email)),
                    ))
                .toList(),
          ),
        ],
        const Spacer(),
        if (_submitError != null) ...[
          Text(_submitError!,
              style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.systemRed.resolveFrom(context)),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
        ],
        CupertinoButton.filled(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const CupertinoActivityIndicator(color: CupertinoColors.white)
              : const Text('Done'),
        ),
        const SizedBox(height: 12),
        CupertinoButton(
          onPressed: _isSubmitting ? null : _submit,
          child: const Text('Skip for now'),
        ),
      ],
    );
  }
}

class _EmailChip extends StatelessWidget {
  const _EmailChip({required this.email, required this.onRemove});

  final String email;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBlue
            .resolveFrom(context)
            .withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(email,
              style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.systemBlue.resolveFrom(context))),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(CupertinoIcons.xmark_circle_fill,
                size: 16,
                color: CupertinoColors.systemBlue.resolveFrom(context)),
          ),
        ],
      ),
    );
  }
}
