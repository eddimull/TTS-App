# Comment Visibility — Design

**Date:** 2026-07-14
**Status:** Approved
**Problem:** The comment system is hard to discover. On the event, rehearsal, and booking detail screens it lives in a small plain-text `CommentsSection` at the very bottom of a long scroll view, and dashboard event cards give no hint that an event has new discussion.

## Goals

- A comment entry point that is visible on detail screens regardless of scroll position.
- Unread-comment signal on dashboard event cards.
- No new networking patterns on the client; reuse `topicThreadProvider` and existing realtime invalidation.

## Non-goals

- Changes to the thread screen, Messages tab, or DM/band-channel chat.
- Inline comment composition on detail screens (the bar opens the thread; typing happens there).

## Part 1 — Pinned comment bar on detail screens

### Component

New `CommentBar` widget in `lib/features/chat/widgets/comment_bar.dart`, plus a small body wrapper (`CommentBarBody`: `Column` → `Expanded(scroll view)` + `CommentBar`) used by:

- `lib/features/events/screens/event_detail_screen.dart` (`kind: 'events'`, `idOrKey: event.key`)
- `lib/features/rehearsals/screens/rehearsal_detail_screen.dart` (`kind: 'rehearsals'`, `idOrKey: '${rehearsal.id}'`)
- `lib/features/bookings/screens/booking_detail_screen.dart` (`kind: 'bookings'`, with `bandId`)

The inline `CommentsSection` is removed from all three screens and the widget deleted (nothing else uses it). `TopicRef` / `topicThreadProvider` exports move to (or are imported directly from) the provider file.

### Appearance

Docked below the scroll content, styled like a Cupertino tab bar: hairline top border, bar background color, bottom safe-area padding. Content row:

- 💬 icon (`CupertinoIcons.chat_bubble`)
- One-line latest comment, ellipsized: **Name:** body (or "📷 Photo" for attachment-only, "Message deleted" for deleted)
- Red unread badge with count when `unreadCount > 0`
- Trailing chevron

Text colors use `context.primaryText` / `context.secondaryText` (dark-mode convention).

### States (data: existing `topicThreadProvider(topic)`)

| State | Bar content |
| --- | --- |
| Loading | Bar shell with muted "Comments" label (no layout jump) |
| Empty | Muted "Add a comment…" — bar always visible for discoverability |
| Error | Muted "Comments unavailable — tap to retry"; tap invalidates the provider |
| Has comments | Latest comment line + unread badge when unread > 0 |

Tap (any non-error state) pushes `/conversations/{conversation.id}` with the conversation title, same as the old "View all" link.

### Realtime

None needed beyond what exists: the Pusher-driven invalidation of `topicThreadProvider` re-renders the bar.

## Part 2 — Unread badge on dashboard event cards

### Backend (TTS repo, Laravel mobile API — PR targets `staging`)

The mobile events index that feeds the dashboard adds `unread_comment_count` per item: the count of messages in the item's topic conversation newer than the requesting member's last-read marker. Computed in one joined query across the page of events — no per-event N+1. Applies to both event and rehearsal summaries (they share the dashboard list). Events with no conversation return 0.

### Flutter

- `EventSummary` gains `unreadCommentCount` (`json['unread_comment_count'] ?? 0` — legacy payloads default to 0).
- `EventCard` shows a small 💬 + count in the top row next to `StatusChip`, only when count > 0.
- Clearing: opening the thread marks it read server-side; the existing read-path invalidation plus dashboard provider refresh clears the badge.

### Realtime

New comments fire the existing band-channel `message` signal; the dashboard provider is added to that signal's invalidation list so badges appear without manual refresh.

## Testing

- Widget tests for `CommentBar` covering the four states, using provider overrides with a fake repository (existing test style, `test/` mirrors `lib/`).
- `EventSummary.fromJson` test for `unread_comment_count` present/absent.
- `EventCard` widget test: badge hidden at 0, shown with count when > 0.
- Backend: feature test asserting `unread_comment_count` in the index payload, including the zero/no-conversation case.

## Rollout

Flutter changes are backward-compatible with a backend that doesn't send `unread_comment_count` (badge simply never shows), so the mobile PR does not hard-depend on the backend deploy. Ship backend to staging first regardless, per usual flow.
