import 'package:flutter/cupertino.dart';
import 'package:tts_bandmate/core/theme/context_colors.dart';
import 'package:tts_bandmate/features/contacts/contact_detail_screen.dart';
import 'package:tts_bandmate/features/contacts/contact_ref.dart';
import 'package:tts_bandmate/features/events/data/models/event_detail.dart';
import 'package:tts_bandmate/features/events/widgets/event_sections/section_primitives.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Contacts ──────────────────────────────────────────────────────────────────

class ContactRow extends StatelessWidget {
  const ContactRow({super.key, required this.contact});
  final EventContact contact;

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ContactDetailScreen(
          contact: ContactRef(
            name: contact.name,
            email: contact.email,
            phone: contact.phone,
            role: contact.role,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openDetail(context),
        child: SectionCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemBlue
                      .resolveFrom(context)
                      .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    contact.name.isNotEmpty
                        ? contact.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: CupertinoColors.systemBlue.resolveFrom(context)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contact.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    if (contact.role != null && contact.role!.isNotEmpty)
                      Text(contact.role!,
                          style: TextStyle(
                              fontSize: 13, color: context.secondaryText)),
                    if (contact.phone != null && contact.phone!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ContactLink(
                        icon: CupertinoIcons.phone,
                        label: contact.phone!,
                        url: 'tel:${contact.phone!}',
                        context: context,
                      ),
                    ],
                    if (contact.email != null && contact.email!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      ContactLink(
                        icon: CupertinoIcons.mail,
                        label: contact.email!,
                        url: 'mailto:${contact.email!}',
                        context: context,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: context.tertiaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ContactLink extends StatelessWidget {
  const ContactLink({
    super.key,
    required this.icon,
    required this.label,
    required this.url,
    required this.context,
  });
  final IconData icon;
  final String label;
  final String url;
  final BuildContext context;

  @override
  Widget build(BuildContext ctx) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri != null) await launchUrl(uri);
      },
      child: Row(
        children: [
          Icon(icon,
              size: 13, color: CupertinoColors.activeBlue.resolveFrom(ctx)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.activeBlue.resolveFrom(ctx)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
