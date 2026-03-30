import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/core_providers.dart';

/// A thumbnail widget that fetches an authenticated image via [CachedNetworkImage].
/// Reads the Bearer token once on init via [secureStorageProvider], then passes
/// it as an Authorization header. Shows a spinner while the token loads.
class AuthThumbnail extends ConsumerStatefulWidget {
  const AuthThumbnail({super.key, required this.url});
  final String url;

  @override
  ConsumerState<AuthThumbnail> createState() => _AuthThumbnailState();
}

class _AuthThumbnailState extends ConsumerState<AuthThumbnail> {
  String? _token;
  bool _tokenLoaded = false;

  @override
  void initState() {
    super.initState();
    ref.read(secureStorageProvider).readToken().then((t) {
      if (mounted) setState(() { _token = t; _tokenLoaded = true; });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_tokenLoaded) {
      return Container(
        color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
        child: const Center(child: CupertinoActivityIndicator(radius: 8)),
      );
    }
    return CachedNetworkImage(
      imageUrl: widget.url,
      httpHeaders: {
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
        child: const Center(child: CupertinoActivityIndicator(radius: 8)),
      ),
      errorWidget: (_, __, ___) => Container(
        color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
        child: Icon(
          CupertinoIcons.photo,
          size: 18,
          color: CupertinoColors.tertiaryLabel.resolveFrom(context),
        ),
      ),
    );
  }
}
