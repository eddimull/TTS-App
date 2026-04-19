import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _passwordVisible = false;
  bool _isSubmitting = false;
  String? _emailError;
  String? _passwordError;
  String? _loginError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _validate() {
    String? emailError;
    String? passwordError;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      emailError = 'Please enter your email.';
    } else if (!email.contains('@')) {
      emailError = 'Enter a valid email address.';
    }

    if (password.isEmpty) {
      passwordError = 'Please enter your password.';
    }

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _loginError = null;
    });
    return emailError == null && passwordError == null;
  }

  Future<void> _submit() async {
    if (!_validate()) return;

    setState(() => _isSubmitting = true);

    await ref.read(authProvider.notifier).login(
          _emailController.text.trim(),
          _passwordController.text,
        );

    if (!mounted) return;
    final authState = ref.read(authProvider).value;
    setState(() {
      _isSubmitting = false;
      if (authState is AuthUnauthenticated) {
        _loginError = authState.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  CupertinoIcons.music_note,
                  size: 72,
                  color: CupertinoColors.systemBlue.resolveFrom(context),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bandmate',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: CupertinoColors.systemBlue.resolveFrom(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'TTS Band Management',
                  style: TextStyle(
                    fontSize: 15,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Email field
                CupertinoTextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  placeholder: 'Email',
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Icon(CupertinoIcons.mail,
                        size: 20, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                    borderRadius: BorderRadius.circular(10),
                    border: _emailError != null
                        ? Border.all(color: CupertinoColors.systemRed.resolveFrom(context))
                        : null,
                  ),
                ),
                if (_emailError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _emailError!,
                    style: TextStyle(
                        fontSize: 12, color: CupertinoColors.systemRed.resolveFrom(context)),
                  ),
                ],
                const SizedBox(height: 16),

                // Password field
                CupertinoTextField(
                  controller: _passwordController,
                  obscureText: !_passwordVisible,
                  textInputAction: TextInputAction.done,
                  placeholder: 'Password',
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Icon(CupertinoIcons.lock,
                        size: 20, color: CupertinoColors.secondaryLabel.resolveFrom(context)),
                  ),
                  suffix: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                      child: Icon(
                        _passwordVisible
                            ? CupertinoIcons.eye_slash
                            : CupertinoIcons.eye,
                        size: 20,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
                    borderRadius: BorderRadius.circular(10),
                    border: _passwordError != null
                        ? Border.all(color: CupertinoColors.systemRed.resolveFrom(context))
                        : null,
                  ),
                ),
                if (_passwordError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _passwordError!,
                    style: TextStyle(
                        fontSize: 12, color: CupertinoColors.systemRed.resolveFrom(context)),
                  ),
                ],
                const SizedBox(height: 32),

                CupertinoButton.filled(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const CupertinoActivityIndicator(
                          color: CupertinoColors.white)
                      : const Text('Sign In',
                          style: TextStyle(fontSize: 16)),
                ),
                if (_loginError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _loginError!,
                    style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.systemRed.resolveFrom(context)),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account?",
                      style: TextStyle(
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.only(left: 4),
                      onPressed: () => context.push('/signup'),
                      child: const Text('Sign up'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
