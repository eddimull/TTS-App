---
name: Library Feature — Implementation
description: Nav swap, chart list/detail screens, create/delete chart, upload/delete uploads, router structure, and Cupertino-specific gotchas
type: project
---

The Library feature replaces Media in the bottom nav (4th tab) and gives Media a home in the More screen instead.

**Why:** Charts (sheet music uploads) needed their own tab-level feature with list + detail navigation, create/delete, and file upload.

**Route structure:**
- `/library` — inside ShellRoute (tab 4 of 5) → `LibraryScreen`
- `/library/new` — outside ShellRoute → `CreateChartScreen(bandId: state.extra as int)`. Must be declared BEFORE `/library/:chartId` in router.dart to prevent "new" being parsed as a chartId.
- `/library/:chartId` — outside ShellRoute → `ChartDetailScreen(bandId: state.extra as int, chartId: ...)`
- `/media` — outside ShellRoute; accessed via `context.push('/media')` from `more_screen.dart`

**bandId threading:** `LibraryScreen` resolves bandId from `selectedBandProvider`, calls `libraryProvider.notifier.load(bandId)` in `initState` via `addPostFrameCallback`, and passes bandId as `extra` to any push (`context.push('/library/${chart.id}', extra: bandId)`). Routes cast `state.extra as int`.

**Provider shape:**
- `libraryProvider` — `AsyncNotifierProvider<LibraryNotifier, LibraryState>`. Notifier has `load(bandId)`, `createChart(bandId, title, {...})` → returns new `Chart`, inserts and re-sorts in state; `deleteChart(bandId, chartId)` → removes from state list. build() returns empty state; callers trigger load explicitly.
- `chartDetailProvider` — `FutureProvider.autoDispose.family<Chart, ({int bandId, int chartId})>`. Retry via `ref.invalidate(...)`.
- `chartUploadProvider` — `AutoDisposeNotifierProvider<ChartUploadNotifier, ChartUploadState>`. Tracks isUploading, progress (0.0–1.0), error, lastUploaded. Methods: `uploadChartFile(...)`, `deleteChartUpload(...)`, `reset()`.

**Upload flow:** `_AddUploadSheet` is a `ConsumerStatefulWidget` shown via `showCupertinoModalPopup`. The modal route loses the ProviderScope ancestor, so re-attach with `UncontrolledProviderScope(container: ProviderScope.containerOf(context), child: ...)`. FilePicker uses `withData: true` to ensure `PlatformFile.bytes` is non-null on all platforms (required for `MultipartFile.fromBytes`). Upload type IDs: 1=Audio, 2=Video, 3=Sheet Music.

**Delete pattern:** Long-press on chart rows in LibraryScreen + trash icon on upload rows in ChartDetailScreen both trigger a `showCupertinoDialog` confirmation before calling the provider method.

**Cupertino gotchas:**
- `Divider` is Material — use `Container(height: 0.5, color: CupertinoColors.separator.resolveFrom(context))`.
- `LinearProgressIndicator` is Material — import it with `import 'package:flutter/material.dart' show LinearProgressIndicator;` (no Cupertino equivalent for linear progress).
- `CupertinoButton.minSize` is deprecated → use `minimumSize: Size.zero`.
- `ProviderScope(parent: ...)` is deprecated → use `UncontrolledProviderScope(container: ...)`.
- `Color.withOpacity()` is deprecated → use `.withValues(alpha: x)`.

**How to apply:** Reference for any feature that needs: create/delete CRUD wired into an existing list provider, file upload with progress in a bottom sheet, and the UncontrolledProviderScope pattern for modals.
