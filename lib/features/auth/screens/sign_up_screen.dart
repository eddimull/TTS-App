import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key, this.prefillEmail});

  /// Pre-filled email from a deep-link invite.
  final String? prefillEmail;

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _passwordVisible = false;
  bool _isSubmitting = false;
  String? _nameError;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    if (widget.prefillEmail != null) {
      _emailController.text = widget.prefillEmail!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool _validate() {
    String? nameError;
    String? emailError;
    String? passwordError;
    String? confirmError;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (name.isEmpty) nameError = 'Please enter your name.';
    if (email.isEmpty) {
      emailError = 'Please enter your email.';
    } else if (!email.contains('@')) {
      emailError = 'Enter a valid email address.';
    }
    if (password.isEmpty) {
      passwordError = 'Please enter a password.';
    } else if (password.length < 8) {
      passwordError = 'Password must be at least 8 characters.';
    }
    if (confirm != password) confirmError = 'Passwords do not match.';

    setState(() {
      _nameError = nameError;
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmError = confirmError;
      _submitError = null;
    });
    return nameError == null &&
        emailError == null &&
        passwordError == null &&
        confirmError == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() => _isSubmitting = true);

    await ref.read(authProvider.notifier).register(
          _nameController.text.trim(),
          _emailController.text.trim(),
          _passwordController.text,
        );

    if (!mounted) return;
    final authState = ref.read(authProvider).value;
    setState(() {
      _isSubmitting = false;
      if (authState is AuthUnauthenticated) {
        _submitError = authState.errorMessage;
      }
    });
    // Router guard handles navigation on success.
  }

  Widget _field({
    required TextEditingController controller,
    required String placeholder,
    required IconData icon,
    String? error,
    bool obscure = false,
    TextInputAction action = TextInputAction.next,
    TextInputType keyboardType = TextInputType.text,
    VoidCallback? onSubmit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          obscureText: obscure,
          textInputAction: action,
          keyboardType: keyboardType,
          autocorrect: false,
          onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
          prefix: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(icon,
                size: 20,
                color: CupertinoColors.secondaryLabel.resolveFrom(context)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
            borderRadius: BorderRadius.circular(10),
            border: error != null
                ? Border.all(
                    color: CupertinoColors.systemRed.resolveFrom(context))
                : null,
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(error,
              style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemRed.resolveFrom(context))),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Create Account')),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                controller: _nameController,
                placeholder: 'Full Name',
                icon: CupertinoIcons.person,
                error: _nameError,
              ),
              const SizedBox(height: 16),
              _field(
                controller: _emailController,
                placeholder: 'Email',
                icon: CupertinoIcons.mail,
                error: _emailError,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              _field(
                controller: _passwordController,
                placeholder: 'Password',
                icon: CupertinoIcons.lock,
                error: _passwordError,
                obscure: !_passwordVisible,
              ),
              const SizedBox(height: 16),
              _field(
                controller: _confirmController,
                placeholder: 'Confirm Password',
                icon: CupertinoIcons.lock_shield,
                error: _confirmError,
                obscure: !_passwordVisible,
                action: TextInputAction.done,
                onSubmit: _submit,
              ),
              const SizedBox(height: 8),
              CupertinoButton(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                onPressed: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
                child: Text(
                  _passwordVisible ? 'Hide passwords' : 'Show passwords',
                  style: TextStyle(
                      fontSize: 13,
                      color:
                          CupertinoColors.systemBlue.resolveFrom(context)),
                ),
              ),
              const SizedBox(height: 24),
              CupertinoButton.filled(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const CupertinoActivityIndicator(
                        color: CupertinoColors.white)
                    : const Text('Create Account',
                        style: TextStyle(fontSize: 16)),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Text(_submitError!,
                    style: TextStyle(
                        fontSize: 13,
                        color:
                            CupertinoColors.systemRed.resolveFrom(context)),
                    textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Already have an account?',
                      style: TextStyle(
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context))),
                  CupertinoButton(
                    padding: const EdgeInsets.only(left: 4),
                    onPressed: () => context.go('/login'),
                    child: const Text('Sign In'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
