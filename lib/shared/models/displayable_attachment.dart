/// Minimal shape shared by any attachment model that can be shown in
/// `AttachmentLightbox` — implemented by both `EventAttachment` and
/// `LodgingAttachment` so the lightbox/URL/icon helpers stay model-agnostic.
///
/// UI-agnostic on purpose: `data/models` classes implement this, so it must
/// not depend on `shared/widgets` (which pulls in Flutter/Cupertino/Dio).
abstract class DisplayableAttachment {
  int get id;
  String get url;
  String get mimeType;
  String get filename;
}
