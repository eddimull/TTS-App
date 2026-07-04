import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../data/native_social_sign_in_service.dart';
import '../data/social_sign_in_service.dart';

final socialSignInServiceProvider = Provider<SocialSignInService>(
  (ref) => NativeSocialSignInService(),
);

/// Mirrors AppConfig.facebookLoginEnabled; a Provider so tests can override.
final facebookLoginEnabledProvider =
    Provider<bool>((ref) => AppConfig.facebookLoginEnabled);
