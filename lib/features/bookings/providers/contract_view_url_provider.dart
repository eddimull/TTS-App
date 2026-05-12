import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_endpoints.dart';
import '../data/bookings_repository.dart';

typedef ContractViewKey = ({int bandId, int bookingId});

final contractViewUrlProvider = FutureProvider.autoDispose
    .family<String, ContractViewKey>((ref, key) async {
  if (kIsWeb) {
    return ref
        .read(bookingsRepositoryProvider)
        .fetchContractViewUrl(key.bandId, key.bookingId);
  }
  return '${AppConfig.baseUrl}'
      '${ApiEndpoints.mobileBookingContractView(key.bandId, key.bookingId)}';
});
