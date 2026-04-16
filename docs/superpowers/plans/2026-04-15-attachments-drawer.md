# Attachments Drawer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fixed attachment panel in the Notes editor with a collapsible drawer that hides when the keyboard is active, supports swipe-to-delete, and tap-to-preview images via lightbox.

**Architecture:** Three tasks in order — (1) extract shared attachment helpers/lightbox to a new file, (2) update both screen files to use the shared file, (3) rebuild the `_NotesEditorSheetState` attachment area with drawer UX. Tasks 1 and 2 must complete before Task 3 since Task 3 imports from the shared file.

**Tech Stack:** Flutter/Dart, Cupertino widgets, `FocusNode`, `AnimatedContainer`, `Dismissible`, `Dio`, `flutter_secure_storage`

---

## Files

| File | Change |
|------|--------|
| `lib/features/events/screens/attachment_widgets.dart` | **Create** — `resolveAttachmentUrl`, `attachmentIcon`, `fetchImageBytes`, `AttachmentLightbox`, `NonImageLightboxPage` |
| `lib/features/events/screens/event_detail_screen.dart` | Remove 5 private symbols, add import |
| `lib/features/events/screens/event_edit_screen.dart` | Remove 2 private symbols, add import; rebuild `_NotesEditorSheetState` |

---

## Task 1: Create `attachment_widgets.dart` with shared helpers and lightbox

**Files:**
- Create: `lib/features/events/screens/attachment_widgets.dart`

- [ ] **Step 1: Create the file with all shared symbols**

  Create `lib/features/events/screens/attachment_widgets.dart` with the following complete content:

  ```dart
  import 'dart:typed_data';
  import 'package:dio/dio.dart';
  import 'package:flutter/cupertino.dart';
  import 'package:flutter_secure_storage/flutter_secure_storage.dart';
  import '../../../core/config/app_config.dart';
  import '../data/models/event_detail.dart';

  // ── URL + icon helpers ────────────────────────────────────────────────────────

  /// Returns the resolved, absolute URL for an attachment.
  /// If [raw] is already absolute (starts with http) it is used as-is.
  /// If it starts with `/` the app's base URL is prepended.
  String resolveAttachmentUrl(String raw) {
    // ignore: avoid_print
    print('[AttachUrl] raw url from API: "$raw"');
    if (raw.isEmpty) return raw;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) return '${AppConfig.baseUrl}$raw';
    return raw;
  }

  IconData attachmentIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return CupertinoIcons.photo;
    if (mimeType == 'application/pdf') return CupertinoIcons.doc_text;
    if (mimeType.startsWith('audio/')) return CupertinoIcons.music_note;
    if (mimeType.startsWith('video/')) return CupertinoIcons.film;
    return CupertinoIcons.doc;
  }

  // ── Lightbox image fetch (full-size, authenticated) ──────────────────────────

  Future<Uint8List?> fetchImageBytes(String url) async {
    try {
      const s = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final token = await s.read(key: 'auth_token');
      final dio = Dio();
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
          validateStatus: (_) => true,
        ),
      );
      if (response.statusCode != 200) return null;
      return Uint8List.fromList(response.data!);
    } catch (_) {
      return null;
    }
  }

  // ── Attachment Lightbox ───────────────────────────────────────────────────────

  class AttachmentLightbox extends StatefulWidget {
    const AttachmentLightbox({
      super.key,
      required this.attachments,
      required this.startIndex,
    });

    /// Image-only attachments to display in the PageView.
    final List<EventAttachment> attachments;
    final int startIndex;

    @override
    State<AttachmentLightbox> createState() => _AttachmentLightboxState();
  }

  class _AttachmentLightboxState extends State<AttachmentLightbox> {
    late final PageController _pageController;
    late int _currentIndex;

    @override
    void initState() {
      super.initState();
      _currentIndex = widget.startIndex;
      _pageController = PageController(initialPage: widget.startIndex);
    }

    @override
    void dispose() {
      _pageController.dispose();
      super.dispose();
    }

    @override
    Widget build(BuildContext context) {
      final attachment = widget.attachments[_currentIndex];
      final isImage = attachment.mimeType.startsWith('image/');

      return CupertinoPageScaffold(
        backgroundColor: CupertinoColors.black,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: CupertinoColors.black.withValues(alpha: 0.85),
          middle: Text(
            attachment.filename,
            style: const TextStyle(color: CupertinoColors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Close',
              style: TextStyle(color: CupertinoColors.systemBlue),
            ),
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              if (isImage)
                PageView.builder(
                  controller: _pageController,
                  itemCount: widget.attachments.length,
                  onPageChanged: (i) => setState(() => _currentIndex = i),
                  itemBuilder: (context, i) {
                    final a = widget.attachments[i];
                    final url = resolveAttachmentUrl(a.url);
                    return InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Center(
                        child: FutureBuilder<Uint8List?>(
                          future: fetchImageBytes(url),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const CupertinoActivityIndicator(
                                  color: CupertinoColors.white);
                            }
                            final bytes = snap.data;
                            if (bytes == null || bytes.isEmpty) {
                              return const Icon(CupertinoIcons.photo,
                                  size: 48, color: CupertinoColors.white);
                            }
                            return Image.memory(bytes, fit: BoxFit.contain);
                          },
                        ),
                      ),
                    );
                  },
                )
              else
                _NonImageLightboxPage(attachment: attachment),
              if (isImage && widget.attachments.length > 1)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.attachments.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _currentIndex ? 10 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _currentIndex
                              ? CupertinoColors.white
                              : CupertinoColors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
  }

  /// Shown in the lightbox for non-image attachment types.
  class _NonImageLightboxPage extends StatelessWidget {
    const _NonImageLightboxPage({super.key, required this.attachment});
    final EventAttachment attachment;

    @override
    Widget build(BuildContext context) {
      final resolvedUrl = resolveAttachmentUrl(attachment.url);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              attachmentIcon(attachment.mimeType),
              size: 64,
              color: CupertinoColors.white.withValues(alpha: 0.85),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                attachment.filename,
                style: const TextStyle(
                    fontSize: 17,
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
            if (resolvedUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                resolvedUrl,
                style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.white.withValues(alpha: 0.5)),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      );
    }
  }
  ```

- [ ] **Step 2: Run analysis on the new file**

  ```bash
  flutter analyze lib/features/events/screens/attachment_widgets.dart
  ```

  Expected: `No issues found!`

  If you get "Undefined name 'AndroidOptions'" — add `import 'package:flutter_secure_storage/flutter_secure_storage.dart';` (already included above). If you get other import errors, check `pubspec.yaml` for `dio`, `flutter_secure_storage`.

- [ ] **Step 3: Commit**

  ```bash
  git add lib/features/events/screens/attachment_widgets.dart
  git commit -m "feat: extract shared attachment helpers and lightbox to attachment_widgets.dart"
  ```

---

## Task 2: Update both screen files to use `attachment_widgets.dart`

**Files:**
- Modify: `lib/features/events/screens/event_detail_screen.dart`
- Modify: `lib/features/events/screens/event_edit_screen.dart`

### `event_detail_screen.dart`

- [ ] **Step 1: Add import to `event_detail_screen.dart`**

  After the existing imports (around line 19), add:

  ```dart
  import 'attachment_widgets.dart';
  ```

- [ ] **Step 2: Remove `_resolveAttachmentUrl` from `event_detail_screen.dart`**

  Delete this entire block (lines ~1014–1024):

  ```dart
  /// Returns the resolved, absolute URL for an attachment.
  /// If [raw] is already absolute (starts with http) it is used as-is.
  /// If it starts with `/` the app's base URL is prepended.
  String _resolveAttachmentUrl(String raw) {
    // ignore: avoid_print
    print('[AttachUrl] raw url from API: "$raw"');
    if (raw.isEmpty) return raw;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (raw.startsWith('/')) return '${AppConfig.baseUrl}$raw';
    return raw;
  }
  ```

- [ ] **Step 3: Remove `_attachmentIcon` from `event_detail_screen.dart`**

  Delete this entire block (lines ~1026–1032):

  ```dart
  IconData _attachmentIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return CupertinoIcons.photo;
    if (mimeType == 'application/pdf') return CupertinoIcons.doc_text;
    if (mimeType.startsWith('audio/')) return CupertinoIcons.music_note;
    if (mimeType.startsWith('video/')) return CupertinoIcons.film;
    return CupertinoIcons.doc;
  }
  ```

- [ ] **Step 4: Remove `_fetchImageBytes` from `event_detail_screen.dart`**

  Delete this entire block (lines ~1168–1190):

  ```dart
  Future<Uint8List?> _fetchImageBytes(String url) async {
    try {
      const s = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      final token = await s.read(key: 'auth_token');
      final dio = Dio();
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
          validateStatus: (_) => true,
        ),
      );
      if (response.statusCode != 200) return null;
      return Uint8List.fromList(response.data!);
    } catch (_) {
      return null;
    }
  }
  ```

- [ ] **Step 5: Remove `_AttachmentLightbox` and `_AttachmentLightboxState` and `_NonImageLightboxPage` from `event_detail_screen.dart`**

  Delete the three classes starting at `// ── Attachment Lightbox ───` (lines ~1192 onward through end of `_NonImageLightboxPage`). These are now in `attachment_widgets.dart`.

- [ ] **Step 6: Replace all call sites in `event_detail_screen.dart`**

  In `_AttachmentRow._handleTap`, change:
  ```dart
  builder: (_) => _AttachmentLightbox(
  ```
  to:
  ```dart
  builder: (_) => AttachmentLightbox(
  ```

  In the `_AttachmentRow.build` and `_NonImageLightboxPage.build` methods, replace:
  - `_resolveAttachmentUrl(` → `resolveAttachmentUrl(`
  - `_attachmentIcon(` → `attachmentIcon(`
  - `_fetchImageBytes(` → `fetchImageBytes(`

  Also in `_AttachmentLightboxState.build` (which you deleted — the remaining `_AttachmentsSection` and `_AttachmentRow` still call the helpers, so update those call sites):
  - Any remaining `_resolveAttachmentUrl(` → `resolveAttachmentUrl(`
  - Any remaining `_attachmentIcon(` → `attachmentIcon(`

- [ ] **Step 7: Run analysis on `event_detail_screen.dart`**

  ```bash
  flutter analyze lib/features/events/screens/event_detail_screen.dart
  ```

  Expected: `No issues found!`

  Common errors and fixes:
  - "Undefined name '_resolveAttachmentUrl'" — you missed a call site; grep for it and update
  - "Unused import 'dart:typed_data'" — remove it if `Uint8List` is no longer referenced
  - "Unused import 'package:dio/dio.dart'" — remove it
  - "Unused import 'package:flutter_secure_storage/...'" — remove it

### `event_edit_screen.dart`

- [ ] **Step 8: Add import to `event_edit_screen.dart`**

  After the existing imports (around line 12), add:

  ```dart
  import 'attachment_widgets.dart';
  ```

- [ ] **Step 9: Remove `_resolveAttachmentUrl` from `event_edit_screen.dart`**

  Delete this block (lines ~1785–1789):

  ```dart
  String _resolveAttachmentUrl(String raw) {
    if (raw.startsWith('http')) return raw;
    if (raw.startsWith('/')) return '${AppConfig.baseUrl}$raw';
    return raw;
  }
  ```

- [ ] **Step 10: Remove `_attachmentIcon` method from `_EventEditScreenState` in `event_edit_screen.dart`**

  Delete this block (lines ~1171–1177, inside the state class):

  ```dart
  IconData _attachmentIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return CupertinoIcons.photo;
    if (mimeType == 'application/pdf') return CupertinoIcons.doc_text;
    if (mimeType.startsWith('audio/')) return CupertinoIcons.music_note;
    if (mimeType.startsWith('video/')) return CupertinoIcons.film;
    return CupertinoIcons.doc;
  }
  ```

- [ ] **Step 11: Replace all call sites in `event_edit_screen.dart`**

  Replace every occurrence of:
  - `_resolveAttachmentUrl(` → `resolveAttachmentUrl(`
  - `_attachmentIcon(` → `attachmentIcon(`

  There are approximately 4 call sites total (2 in `_NotesEditorSheetState.build`, 2 passed as callbacks elsewhere). Use grep to find them all:

  ```bash
  grep -n "_resolveAttachmentUrl\|_attachmentIcon" lib/features/events/screens/event_edit_screen.dart
  ```

  Update every line returned.

- [ ] **Step 12: Run analysis on `event_edit_screen.dart`**

  ```bash
  flutter analyze lib/features/events/screens/event_edit_screen.dart
  ```

  Expected: `No issues found!`

  Common errors and fixes:
  - "Undefined name '_resolveAttachmentUrl'" — missed call site; grep and fix
  - "The method '_attachmentIcon' isn't defined" — missed call site; grep and fix
  - "Unused import '...app_config.dart'" — keep it, `AppConfig` is still used elsewhere in the file

- [ ] **Step 13: Run full project analysis**

  ```bash
  flutter analyze
  ```

  Expected: `No issues found!`

- [ ] **Step 14: Commit**

  ```bash
  git add lib/features/events/screens/event_detail_screen.dart \
          lib/features/events/screens/event_edit_screen.dart
  git commit -m "refactor: use shared attachment_widgets.dart in both screen files"
  ```

---

## Task 3: Rebuild attachment area in `_NotesEditorSheet`

**Files:**
- Modify: `lib/features/events/screens/event_edit_screen.dart`

This task replaces the entire attachment section inside `_NotesEditorSheetState` (the fixed-height panel at the bottom of the Notes fullscreen editor) with the new collapsible drawer UX.

### Background: what `_NotesEditorSheet` currently looks like

The sheet is a `CupertinoPageScaffold` with a nav bar (Cancel / Notes / Done) and a `SafeArea` containing a `Column`:
- `Expanded` text field
- `Container(height: 0.5)` separator
- `Container(maxHeight: 280)` attachment panel

The state has: `_ctrl` (TextEditingController), `_attachments`, `_uploading`.

### New state fields

- [ ] **Step 1: Add new state fields and FocusNode to `_NotesEditorSheetState`**

  In `_NotesEditorSheetState`, add these fields after `bool _uploading = false;`:

  ```dart
  late final FocusNode _focusNode;
  bool _drawerOpen = false;
  bool _keyboardVisible = false;
  ```

- [ ] **Step 2: Wire up `_focusNode` in `initState`**

  Replace the current `initState`:

  ```dart
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialNotes);
    _attachments = List.of(widget.attachments);
  }
  ```

  With:

  ```dart
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialNotes);
    _attachments = List.of(widget.attachments);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      setState(() => _keyboardVisible = _focusNode.hasFocus);
    });
  }
  ```

- [ ] **Step 3: Dispose `_focusNode` in `dispose`**

  Replace the current `dispose`:

  ```dart
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }
  ```

  With:

  ```dart
  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }
  ```

- [ ] **Step 4: Add `focusNode` to the `CupertinoTextField`**

  Find the `CupertinoTextField` inside `_NotesEditorSheetState.build`. It currently starts with:

  ```dart
  child: CupertinoTextField(
    controller: _ctrl,
    placeholder: 'Add notes…',
  ```

  Add `focusNode: _focusNode,` as the second argument:

  ```dart
  child: CupertinoTextField(
    controller: _ctrl,
    focusNode: _focusNode,
    placeholder: 'Add notes…',
  ```

- [ ] **Step 5: Replace the attachment area in `_NotesEditorSheetState.build`**

  Find the current attachment area in `build`. It starts after the `Expanded` text field child and looks like:

  ```dart
            // ── Divider before attachments ──────────────────────────────────
            Container(height: 0.5, color: separatorColor),

            // ── Attachments list + add button ───────────────────────────────
            Container(
              color: CupertinoColors.tertiarySystemBackground.resolveFrom(context),
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                ...
              ),
            ),
  ```

  Delete everything from `// ── Divider before attachments` to the closing `),` of the outer `Container`, and replace with:

  ```dart
            // ── Attachment drawer ───────────────────────────────────────────
            if (!_keyboardVisible) ...[
              _AttachmentDrawerBar(
                count: _attachments.length,
                open: _drawerOpen,
                onTap: () => setState(() => _drawerOpen = !_drawerOpen),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                height: _drawerOpen ? 260.0 : 0.0,
                child: ClipRect(
                  child: _AttachmentDrawerContent(
                    attachments: _attachments,
                    uploading: _uploading,
                    onUpload: _handleUpload,
                    onDelete: _handleDelete,
                  ),
                ),
              ),
            ],
  ```

- [ ] **Step 6: Run analysis — expect errors about missing widgets**

  ```bash
  flutter analyze lib/features/events/screens/event_edit_screen.dart
  ```

  Expected errors: `_AttachmentDrawerBar` and `_AttachmentDrawerContent` are not defined yet. Proceed to next steps.

- [ ] **Step 7: Add `_AttachmentDrawerBar` widget at bottom of file**

  After the closing `}` of `_SheetDragHandle` (the last class in the file), add:

  ```dart
  // ── Attachment drawer bar ─────────────────────────────────────────────────────

  class _AttachmentDrawerBar extends StatelessWidget {
    const _AttachmentDrawerBar({
      required this.count,
      required this.open,
      required this.onTap,
    });
    final int count;
    final bool open;
    final VoidCallback onTap;

    @override
    Widget build(BuildContext context) {
      final separatorColor = CupertinoColors.separator.resolveFrom(context);
      final secondaryBg =
          CupertinoColors.secondarySystemBackground.resolveFrom(context);
      final labelColor = CupertinoColors.label.resolveFrom(context);
      final secondaryLabel =
          CupertinoColors.secondaryLabel.resolveFrom(context);

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 0.5, color: separatorColor),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              color: secondaryBg,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(CupertinoIcons.paperclip, size: 16, color: secondaryLabel),
                  const SizedBox(width: 8),
                  Text(
                    'Attachments ($count)',
                    style: TextStyle(fontSize: 15, color: labelColor),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: Icon(
                      CupertinoIcons.chevron_up,
                      size: 14,
                      color: secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
  }
  ```

- [ ] **Step 8: Add `_AttachmentDrawerContent` widget at bottom of file**

  After `_AttachmentDrawerBar`, add:

  ```dart
  // ── Attachment drawer content ─────────────────────────────────────────────────

  class _AttachmentDrawerContent extends StatelessWidget {
    const _AttachmentDrawerContent({
      required this.attachments,
      required this.uploading,
      required this.onUpload,
      required this.onDelete,
    });
    final List<EventAttachment> attachments;
    final bool uploading;
    final VoidCallback onUpload;
    final Future<void> Function(EventAttachment) onDelete;

    @override
    Widget build(BuildContext context) {
      final separatorColor = CupertinoColors.separator.resolveFrom(context);
      final secondaryBg =
          CupertinoColors.secondarySystemBackground.resolveFrom(context);
      final blueColor = CupertinoColors.activeBlue.resolveFrom(context);
      final secondaryLabel =
          CupertinoColors.secondaryLabel.resolveFrom(context);

      return Container(
        color: secondaryBg,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Add Files button ──────────────────────────────────────────
              CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                onPressed: uploading ? null : onUpload,
                child: Row(
                  children: [
                    if (uploading)
                      const CupertinoActivityIndicator()
                    else
                      Icon(CupertinoIcons.plus_circle,
                          size: 18, color: blueColor),
                    const SizedBox(width: 8),
                    Text(
                      uploading ? 'Uploading…' : 'Add Files',
                      style: TextStyle(
                        fontSize: 15,
                        color: uploading ? secondaryLabel : blueColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 0.5, color: separatorColor),
              // ── File rows ────────────────────────────────────────────────
              for (int i = 0; i < attachments.length; i++) ...[
                if (i > 0)
                  Container(
                    height: 0.5,
                    margin: const EdgeInsets.only(left: 16),
                    color: separatorColor,
                  ),
                Dismissible(
                  key: ValueKey(attachments[i].id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(CupertinoIcons.delete,
                        color: CupertinoColors.white, size: 20),
                  ),
                  onDismissed: (_) => onDelete(attachments[i]),
                  child: _AttachmentDrawerRow(attachment: attachments[i]),
                ),
              ],
            ],
          ),
        ),
      );
    }
  }
  ```

- [ ] **Step 9: Add `_AttachmentDrawerRow` widget at bottom of file**

  After `_AttachmentDrawerContent`, add:

  ```dart
  // ── Attachment drawer row ─────────────────────────────────────────────────────

  class _AttachmentDrawerRow extends StatelessWidget {
    const _AttachmentDrawerRow({required this.attachment});
    final EventAttachment attachment;

    @override
    Widget build(BuildContext context) {
      final isImage = attachment.mimeType.startsWith('image/');
      final resolvedUrl = resolveAttachmentUrl(attachment.url);
      final secondaryLabel =
          CupertinoColors.secondaryLabel.resolveFrom(context);
      final secondaryBg =
          CupertinoColors.secondarySystemBackground.resolveFrom(context);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isImage
            ? () {
                // Build image-only list from context is not available here;
                // we open the lightbox with just this single attachment.
                Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) => AttachmentLightbox(
                      attachments: [attachment],
                      startIndex: 0,
                    ),
                  ),
                );
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: isImage && resolvedUrl.isNotEmpty
                      ? AuthThumbnail(url: resolvedUrl)
                      : ColoredBox(
                          color: secondaryBg,
                          child: Center(
                            child: Icon(
                              attachmentIcon(attachment.mimeType),
                              size: 18,
                              color: secondaryLabel,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.filename,
                      style: const TextStyle(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      attachment.formattedSize,
                      style: TextStyle(fontSize: 12, color: secondaryLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  ```

  **Note on lightbox:** `_AttachmentDrawerRow` opens the lightbox with `[attachment]` (a single-item list). The multi-image PageView swipe is only available from the detail screen where the full list is accessible. This is acceptable for the editor — the user taps a single image to preview it.

- [ ] **Step 10: Run analysis**

  ```bash
  flutter analyze lib/features/events/screens/event_edit_screen.dart
  ```

  Expected: `No issues found!`

  Common errors and fixes:
  - `"The argument type 'Future<void> Function(EventAttachment)' can't be assigned"` — check `_handleDelete` signature in `_NotesEditorSheetState`. It currently returns `Future<void>`. The `onDelete` field in `_AttachmentDrawerContent` must match: `Future<void> Function(EventAttachment)`.
  - `"Undefined name 'AuthThumbnail'"` — ensure `import '../../../shared/widgets/auth_thumbnail.dart';` is present in `event_edit_screen.dart` (it already is).
  - `"Undefined name 'AttachmentLightbox'"` — ensure `import 'attachment_widgets.dart';` was added in Task 2.

- [ ] **Step 11: Run full project analysis**

  ```bash
  flutter analyze
  ```

  Expected: `No issues found!`

- [ ] **Step 12: Commit**

  ```bash
  git add lib/features/events/screens/event_edit_screen.dart
  git commit -m "feat: replace fixed attachment panel with collapsible drawer in notes editor"
  ```

---

## Task 4: Manual verification

Run the app and verify all states from the design spec.

```bash
flutter run -d linux
# or: flutter run  (with a connected iOS/Android device)
```

- [ ] **Keyboard hidden — bar visible**
  1. Open any event → tap Notes preview card
  2. Notes editor opens, keyboard is visible (autofocus)
  3. Tap "Done" or tap background to dismiss keyboard
  4. **Expected:** "Attachments (N)" bar appears at the bottom with correct count

- [ ] **Keyboard visible — bar hidden**
  1. Tap the notes text area to focus
  2. **Expected:** attachment bar disappears entirely

- [ ] **Drawer toggle**
  1. With keyboard dismissed, tap the "Attachments (N)" bar
  2. **Expected:** drawer animates open (260px), chevron rotates 180°
  3. Tap bar again
  4. **Expected:** drawer collapses, chevron rotates back

- [ ] **Count updates**
  1. Open drawer, tap "Add Files", upload a file
  2. **Expected:** count in header increments immediately

- [ ] **Swipe-to-delete**
  1. With drawer open and at least one file, swipe left on a file row
  2. **Expected:** red delete background revealed with trash icon
  3. Complete the swipe
  4. **Expected:** row removed, count decrements

- [ ] **Tap image to preview**
  1. With an image attachment, tap its row
  2. **Expected:** `AttachmentLightbox` opens fullscreen with the image

- [ ] **Tap non-image — no action**
  1. With a non-image attachment (e.g. PDF), tap its row
  2. **Expected:** nothing happens

- [ ] **Keyboard + drawer state independence**
  1. Open drawer, then tap text area to focus keyboard
  2. **Expected:** drawer bar disappears (drawer open state is preserved)
  3. Dismiss keyboard
  4. **Expected:** bar returns — drawer is still open (its state was not reset)

- [ ] **Done / Cancel still work**
  1. Open Notes editor, make a change, tap Done
  2. **Expected:** returns to edit screen with notes updated
  3. Open again, make a change, tap Cancel
  4. **Expected:** returns without saving

- [ ] **No regression on event detail screen**
  1. Navigate to any event detail screen that has attachments
  2. **Expected:** `_AttachmentsSection` renders identically to before (read-only rows, lightbox still works)
