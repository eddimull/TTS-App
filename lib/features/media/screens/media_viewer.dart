import 'dart:async';
import 'package:dio/dio.dart' as dio_pkg;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Slider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../../core/config/app_config.dart';
import '../../../core/providers/core_providers.dart';
import '../../../shared/widgets/auth_thumbnail.dart';
import '../data/models/media_file.dart';

class MediaViewer extends ConsumerStatefulWidget {
  const MediaViewer({super.key, required this.file});

  final MediaFile file;

  @override
  ConsumerState<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends ConsumerState<MediaViewer> {
  VideoPlayerController? _videoController;
  AudioPlayer? _audioPlayer;
  bool _showInfo = false;
  bool _isDownloading = false;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    if (widget.file.isVideo) _initVideo();
    if (widget.file.isAudio) _initAudio();
  }

  Future<void> _initVideo() async {
    final token = await ref.read(secureStorageProvider).readToken();
    final uri = Uri.parse('${AppConfig.baseUrl}/media/${widget.file.id}/serve');
    _videoController = VideoPlayerController.networkUrl(
      uri,
      httpHeaders: {if (token != null) 'Authorization': 'Bearer $token'},
    );
    await _videoController!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _initAudio() async {
    _audioPlayer = AudioPlayer();
    final token = await ref.read(secureStorageProvider).readToken();
    final uri = Uri.parse('${AppConfig.baseUrl}/media/${widget.file.id}/serve');
    await _audioPlayer!.setUrl(
      uri.toString(),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    setState(() { _isDownloading = true; _downloadError = null; });
    try {
      final token = await ref.read(secureStorageProvider).readToken();
      final url = '${AppConfig.baseUrl}/media/${widget.file.id}/serve';
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/${widget.file.filename}';
      final dio = ref.read(apiClientProvider).dio;
      await dio.download(
        url,
        path,
        options: dio_pkg.Options(
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
      await OpenFile.open(path);
    } catch (e) {
      if (mounted) setState(() => _downloadError = 'Download failed: $e');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          Navigator.pop(context);
        }
      },
      child: CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: const Color(0xCC000000),
        middle: Text(
          widget.file.title,
          style: const TextStyle(color: CupertinoColors.white),
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.xmark, color: CupertinoColors.white),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.file.isImage || widget.file.isVideo || widget.file.isAudio)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _showInfo = !_showInfo),
                child: Icon(
                  _showInfo ? CupertinoIcons.info_circle_fill : CupertinoIcons.info_circle,
                  color: CupertinoColors.white,
                ),
              ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _isDownloading ? null : _download,
              child: const Icon(CupertinoIcons.arrow_down_circle, color: CupertinoColors.white),
            ),
          ],
        ),
      ),
      child: Stack(
        children: [
          _buildContent(),
          if (_showInfo) _buildInfoOverlay(context),
          if (_downloadError != null)
            Positioned(
              bottom: 40,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemRed.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_downloadError!,
                    style: const TextStyle(color: CupertinoColors.white, fontSize: 13)),
              ),
            ),
        ],
      ),
    ),
    );
  }

  Widget _buildContent() {
    if (widget.file.isImage) return _buildImageViewer();
    if (widget.file.isVideo) return _buildVideoViewer();
    if (widget.file.isAudio) return _buildAudioViewer();
    return _buildDocumentView();
  }

  Widget _buildImageViewer() {
    final url = '${AppConfig.baseUrl}/media/${widget.file.id}/serve';
    return Center(
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: AuthThumbnail(url: url),
      ),
    );
  }

  Widget _buildVideoViewer() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const Center(child: CupertinoActivityIndicator(color: CupertinoColors.white));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
        const SizedBox(height: 16),
        _VideoControls(controller: _videoController!),
      ],
    );
  }

  Widget _buildAudioViewer() {
    if (_audioPlayer == null) {
      return const Center(child: CupertinoActivityIndicator(color: CupertinoColors.white));
    }
    return Center(child: _AudioControls(player: _audioPlayer!, file: widget.file));
  }

  Widget _buildDocumentView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.doc_text,
              size: 72, color: CupertinoColors.white.withValues(alpha: 0.8)),
          const SizedBox(height: 16),
          Text(widget.file.filename,
              style: const TextStyle(color: CupertinoColors.white, fontSize: 16),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(widget.file.formattedSize,
              style: TextStyle(
                  color: CupertinoColors.white.withValues(alpha: 0.6), fontSize: 13)),
          const SizedBox(height: 24),
          if (_isDownloading)
            const CupertinoActivityIndicator(color: CupertinoColors.white)
          else
            CupertinoButton.filled(
              onPressed: _download,
              child: const Text('Download & Open'),
            ),
          if (_downloadError != null) ...[
            const SizedBox(height: 8),
            Text(_downloadError!,
                style: const TextStyle(color: CupertinoColors.systemRed, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoOverlay(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xDD000000), Color(0x00000000)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.file.title,
                style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              '${widget.file.mediaType.toUpperCase()} · ${widget.file.formattedSize}'
              '${widget.file.folderPath != null ? ' · ${widget.file.folderPath}' : ''}',
              style: TextStyle(
                  color: CupertinoColors.white.withValues(alpha: 0.7), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoControls extends StatefulWidget {
  const _VideoControls({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  late VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _listener = () { if (mounted) setState(() {}); };
    widget.controller.addListener(_listener);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = widget.controller.value.isPlaying;
    final position = widget.controller.value.position;
    final duration = widget.controller.value.duration;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Slider(
            value: duration.inMilliseconds > 0
                ? position.inMilliseconds / duration.inMilliseconds
                : 0.0,
            onChanged: (v) => widget.controller
                .seekTo(Duration(milliseconds: (v * duration.inMilliseconds).toInt())),
            activeColor: CupertinoColors.white,
            inactiveColor: CupertinoColors.white.withValues(alpha: 0.3),
          ),
          CupertinoButton(
            onPressed: isPlaying ? widget.controller.pause : widget.controller.play,
            child: Icon(
              isPlaying ? CupertinoIcons.pause_circle_fill : CupertinoIcons.play_circle_fill,
              size: 48,
              color: CupertinoColors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioControls extends StatefulWidget {
  const _AudioControls({required this.player, required this.file});
  final AudioPlayer player;
  final MediaFile file;

  @override
  State<_AudioControls> createState() => _AudioControlsState();
}

class _AudioControlsState extends State<_AudioControls> {
  late StreamSubscription<PlayerState> _stateSub;
  late StreamSubscription<Duration> _posSub;

  @override
  void initState() {
    super.initState();
    _stateSub = widget.player.playerStateStream.listen((_) { if (mounted) setState(() {}); });
    _posSub   = widget.player.positionStream.listen((_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _stateSub.cancel();
    _posSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = widget.player.playing;
    final position = widget.player.position;
    final duration = widget.player.duration ?? Duration.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.music_note,
              size: 80, color: CupertinoColors.white.withValues(alpha: 0.6)),
          const SizedBox(height: 24),
          Text(widget.file.title,
              style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Slider(
            value: duration.inMilliseconds > 0
                ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
                : 0.0,
            onChanged: (v) => widget.player
                .seek(Duration(milliseconds: (v * duration.inMilliseconds).toInt())),
            activeColor: CupertinoColors.white,
            inactiveColor: CupertinoColors.white.withValues(alpha: 0.3),
          ),
          CupertinoButton(
            onPressed: isPlaying ? widget.player.pause : widget.player.play,
            child: Icon(
              isPlaying ? CupertinoIcons.pause_circle_fill : CupertinoIcons.play_circle_fill,
              size: 56,
              color: CupertinoColors.white,
            ),
          ),
        ],
      ),
    );
  }
}
