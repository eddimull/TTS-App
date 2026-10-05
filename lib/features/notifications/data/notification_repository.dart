import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import 'models/notification_item.dart';

class NotificationRepository {
  NotificationRepository(this._dio);
  final Dio _dio;

  Future<NotificationPage> list({String? cursor, int limit = 30}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.mobileNotifications,
      queryParameters: {if (cursor != null) 'cursor': cursor, 'limit': limit},
    );
    final data = res.data ?? const {};
    return NotificationPage(
      items: (data['notifications'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(NotificationItem.fromJson)
          .toList(),
      nextCursor: data['next_cursor']?.toString(),
      unseenCount: (data['unseen_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<int> unseenCount() async {
    final res = await _dio.get<Map<String, dynamic>>(ApiEndpoints.mobileNotificationsUnseen);
    return (res.data?['count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markRead(String id) => _dio.post<void>(ApiEndpoints.mobileNotificationRead(id));
  Future<void> markAllRead() => _dio.post<void>(ApiEndpoints.mobileNotificationsReadAll);
  Future<void> markSeen() => _dio.post<void>(ApiEndpoints.mobileNotificationsSeen);
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(apiClientProvider).dio);
});
