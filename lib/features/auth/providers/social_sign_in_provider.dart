import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/native_social_sign_in_service.dart';
import '../data/social_sign_in_service.dart';

final socialSignInServiceProvider = Provider<SocialSignInService>(
  (ref) => NativeSocialSignInService(),
);
