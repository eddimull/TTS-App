/// The set of subscription URLs for the user's personal calendar feed.
///
/// - [url]: the plain https `.ics` feed (good for "copy link").
/// - [webcalUrl]: the same feed with a `webcal://` scheme, which makes Apple
///   Calendar / Outlook subscribe (rather than download) when opened.
/// - [googleSubscribeUrl]: a deep link into Google Calendar's "add by URL"
///   flow, prefilled with the feed.
class CalendarFeed {
  const CalendarFeed({
    required this.url,
    required this.webcalUrl,
    required this.googleSubscribeUrl,
  });

  final String url;
  final String webcalUrl;
  final String googleSubscribeUrl;

  factory CalendarFeed.fromJson(Map<String, dynamic> json) {
    return CalendarFeed(
      url: json['url'] as String,
      webcalUrl: json['webcal_url'] as String,
      googleSubscribeUrl: json['google_subscribe_url'] as String,
    );
  }
}
