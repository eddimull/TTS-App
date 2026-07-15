# Questionnaires on Mobile — Design

**Date:** 2026-07-15
**Repos:** `tts_bandmate` (Flutter) + `TTS` (Laravel backend, PRs target `staging`)
**Branch:** `feat/questionnaires-mobile` (mobile); backend branches per phase

## Goal

Bring the existing web questionnaires feature to the mobile app at full parity:
template CRUD (including the full field builder), sending to booking contacts,
sent-instance logs, viewing responses, applying answers to events, and push
notifications on submission. Entry point lives in the hamburger (Operations)
menu.

There is currently **no mobile API for questionnaires** — every endpoint below
is net-new backend work, implemented as thin controllers over the existing
services (`QuestionnaireSnapshotService`, `QuestionnaireMappingService`,
`FieldSettingsValidator`, `QuestionnaireFieldTypeRegistry`,
`QuestionnaireMappingRegistry`, `QuestionnairePresetRegistry`,
`QuestionnaireVisibilityEvaluator`). No business logic is duplicated; where web
controller logic is needed (the diff-based bulk field upsert), it is extracted
into a shared service both web and mobile call.

## Decisions (from brainstorming)

- **Builder scope:** full parity — all 13 field types, reorder, per-type
  settings, visibility rules, mapping targets, presets.
- **Notifications:** push on submission (and re-submission) to **all owner
  users**, deep-linking to the responses screen. Contact-facing emails
  unchanged. (This also upgrades the web behavior of notifying only the first
  owner.)
- **Apply-to-event:** included — per-field apply, apply-all, append-to-notes.
- **Send entry points:** both the questionnaire detail screen (pick booking +
  recipient) and the booking detail screen (pick template + recipient), with
  instance actions (resend/lock/unlock/delete) in both.
- **Permissions:** match web — all members see the menu entry; read-only for
  non-owners (list/logs/responses); create/edit/send/apply are owner-gated in
  the UI (`currentBand.isOwner`) and permission-enforced server-side
  (`read:questionnaires` / `write:questionnaires`; apply additionally requires
  `write:events`).
- **Delivery:** three phased vertical slices, each a backend PR + mobile PR,
  independently shippable and on-device verified.

## Phases

### Phase 1 — Templates (CRUD + builder)

**Backend** (`Api/Mobile/QuestionnaireController`, Sanctum, band-scoped under
`/api/mobile/bands/{band}`; templates addressed by **id**, not slug):

| Method | Path | Behavior |
|---|---|---|
| GET | `/questionnaires` | List incl. archived; status + times-sent count |
| GET | `/questionnaires/catalog` | Field-type, mapping-target, preset catalogs (static registries) |
| POST | `/questionnaires` | Create: `name`, `description`, optional `preset_key` (server clones preset fields) |
| GET | `/questionnaires/{id}` | Detail with ordered fields |
| PUT | `/questionnaires/{id}` | Diff-based bulk field upsert — same payload as web: delete missing, upsert present, client temp-ids (`new-N`) for new fields, two-pass rewrite of `visibility_rule.depends_on`; per-type settings validation, mapping/type compatibility, forward-only visibility references |
| POST | `/questionnaires/{id}/archive`, `/restore` | Toggle archived |
| DELETE | `/questionnaires/{id}` | 409 if instances exist |

**Mobile** — new `lib/features/questionnaires/` slice on the Personnel pattern:

```
data/models/        questionnaire, questionnaire_field, questionnaire_instance,
                    instance_field, questionnaire_response, catalogs
data/questionnaires_repository.dart
providers/          questionnaires_provider (AsyncNotifier.family by bandId),
                    questionnaire_detail_provider, instances_provider,
                    instance_detail_provider, catalog_provider
screens/            questionnaires_screen, questionnaire_editor_screen,
                    questionnaire_detail_screen, instance_responses_screen
widgets/            field editor pieces, send sheet, status badge, …
```

- `NavRow` "Questionnaires" in `operations_screen.dart`, visible to all
  members; routes inside the ShellRoute: `/questionnaires`,
  `/questionnaires/:id`, `/questionnaires/:id/edit`,
  `/questionnaires/:id/instances/:instanceId`.
- Endpoint builders added to `api_endpoints.dart` under a Questionnaires
  banner (`mobileBandQuestionnaires(bandId)` etc.).
- **List screen:** active + archived sections, create sheet with name,
  description, preset picker (Blank / Wedding).
- **Builder screen:** name/description; `ReorderableListView` of field cards
  (type icon, label, required dot, chips for options/visibility/mapping);
  add-field type picker grouped Input vs Display; duplicate/delete; dirty
  tracking with discard confirm; single bulk-save PUT.
- **Per-field editor screen:** label, help text, required; type-specific
  settings — option row editor (dropdown/multi-select/checkbox-group), purpose
  picker (song_picker: must_play/do_not_play/general); mapping-target picker
  filtered to type-compatible targets; visibility-rule builder (earlier field
  + operator equals/not_equals/contains/empty/not_empty + adaptive value
  input). Changing type clears incompatible settings after a confirm.
- **Preview:** read-only rendering of all field types honoring visibility
  rules via a Dart port of the visibility evaluator (mirrors `visibility.js`;
  unit-tested against the same cases).

### Phase 2 — Sending, logs, booking integration, realtime

**Backend** (`Api/Mobile/QuestionnaireInstanceController` + booking routes):

| Method | Path | Behavior |
|---|---|---|
| GET | `/questionnaires/{id}/instances` | Logs: booking, recipient, dates, status |
| GET | `/questionnaires/{id}/eligible-bookings` | Future-dated bookings, portal-enabled contacts, `already_sent` flags |
| POST | `/bookings/{booking}/questionnaires` | Send: snapshot + `QuestionnaireSent` notification (same `SendQuestionnaireRequest` rules incl. `can_login` check) |
| GET | `/bookings/{booking}/questionnaire-instances` | Booking's instances + available templates |
| GET | `/questionnaire-instances/{id}` | Frozen fields + responses (values decoded, song IDs resolved to titles) |
| POST | `/questionnaire-instances/{id}/resend`, `/lock`, `/unlock` | Same semantics as web (unlock recomputes status) |
| DELETE | `/questionnaire-instances/{id}` | Soft delete |

Questionnaire models emit the thin `BandDataChanged` broadcast
(`{model, id, action}` on `private-band.{id}`).

**Mobile:**

- **Questionnaire detail screen:** template summary + actions
  (Edit/Preview/Archive/Delete), Send button, and the **Sent** log list —
  status badges (sent/in progress/submitted/locked), status filter chips,
  sent/submitted dates; rows push the responses screen; context-menu instance
  actions with confirm on delete.
- **Send sheet:** eligible booking picker (already-sent flagged, re-send
  allowed) → recipient picker (portal-enabled contacts) → confirm; inline
  errors.
- **Responses screen:** recipient + status header; fields in order with
  answers — multi-select as chips, songs as "Title — Artist", headers/
  instructions as section breaks, unanswered muted, visibility-hidden fields
  omitted.
- **Booking detail screen:** Questionnaires section — instances with status,
  tap-through to responses, "Send questionnaire" action.
- **Realtime:** `questionnaires`, `questionnaire_instances`,
  `questionnaire_responses` cases in `invalidationTargetsFor`
  (band_realtime_provider.dart) + `_allRegisteredModels`.

### Phase 3 — Apply-to-event + push

**Backend:**

| Method | Path | Behavior |
|---|---|---|
| POST | `/questionnaire-instances/{id}/responses/{responseId}/apply` | `QuestionnaireMappingService::applyResponse`; requires `write:events` too |
| POST | `/questionnaire-instances/{id}/apply-all` | All pending mapped responses |
| POST | `/questionnaire-instances/{id}/append-to-notes` | `appendAllToNotes` |

`QuestionnaireSubmitted` extended: recipients become **all owner users** (not
just the first), and a data-only FCM push is sent via the existing
`SendUserPush` layer — `type=questionnaire_submitted`, `band_id`,
`questionnaire_id`, `instance_id`, plus display strings ("«Contact» submitted
«Name»", "updated" wording on re-submission).

**Mobile:**

- Responses screen: **Apply** button per mapped field with three states — not
  applied / applied ✓ / needs re-apply (`updated_at > applied_to_event_at`);
  toolbar **Apply all pending** and **Append all to notes** (confirmed).
  Owner-only UI.
- Push: `questionnaire_submitted` added to `PushType`/`push_payload.dart`,
  `routeForPushData` → `/questionnaires/{questionnaireId}/instances/{instanceId}`,
  and `buildBackgroundNotification` (data-only rendering).

## Error handling

- Repository/provider errors via existing `AsyncValue.guard` + optimistic
  revert patterns.
- DELETE 409 → "This questionnaire has been sent and can't be deleted —
  archive it instead."
- 403 → read-only rendering, not a crash.
- Send validation failures (recipient without portal login, archived template)
  surface inline in the send sheet.

## Testing & verification

- **Backend:** feature tests per endpoint (auth, band scoping, permissions,
  validation, snapshot/mapping behavior) via `docker compose exec app php
  artisan test`; PRs target `staging`.
- **Flutter:** model `fromJson` tests, provider tests with fake repositories,
  visibility-evaluator port tested against the web spec's cases; `flutter
  analyze` + `flutter test`; version bump in the final mobile PR.
- **On-device:** each phase verified on the physical device against the local
  backend, including the push deep link. Note: mobile token abilities are
  baked into issued tokens — re-login after backend deploy if new ability
  names are introduced.

## Out of scope

- Contact portal (response filling) — contacts keep using the web portal.
- Changes to web UI beyond the shared field-upsert service extraction and the
  owner-notification recipient fix.
- Per-key (parent-scoped) realtime invalidation — band-wide family
  invalidation is the established v1 pattern.
