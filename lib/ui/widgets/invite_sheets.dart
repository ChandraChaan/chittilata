import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/contact_invite.dart';
import '../../core/services/invite_links.dart';
import '../../core/theme/app_theme.dart';
import 'common.dart';

/// A big QR code of the room's invite link, for friends sitting at the same
/// table: they scan it with their phone camera, which opens ChitPlay straight
/// into the room (or the Play Store page if it isn't installed).
Future<void> showInviteQr(BuildContext context, String code) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final c = ctx.colors;
      final side = (MediaQuery.sizeOf(ctx).width * 0.62).clamp(160.0, 300.0);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Scan to join', style: ctx.text.titleLarge),
              const SizedBox(height: Space.xs),
              Text(
                'Friends point their phone camera at this code.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
              const SizedBox(height: Space.lg),
              Semantics(
                label: 'QR code to join room $code',
                image: true,
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.all(Space.md),
                  decoration: BoxDecoration(
                    // Scanners want dark modules on a light background,
                    // whatever the app theme.
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.marigold, width: 3),
                  ),
                  child: QrImageView(
                    data: InviteLinks.linkFor(code).toString(),
                    size: side,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF1E1140),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF1E1140),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.lg),
              Text(
                code,
                style: ctx.text.headlineMedium?.copyWith(
                  color: c.marigold,
                  letterSpacing: 6,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'or type the room code in ChitPlay',
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Picks one friend from the address book (no contacts permission needed)
/// and sends them the invite by WhatsApp or SMS.
Future<void> inviteContact(BuildContext context, String code) async {
  final contact = await ContactInvite.pick();
  if (contact == null || !context.mounted) return;
  final text = InviteLinks.message(code);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      Future<void> open(Uri uri) async {
        Navigator.pop(ctx);
        final ok = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        ).catchError((_) => false);
        if (!ok && context.mounted) {
          showGameSnack(context, "Couldn't open that app");
        }
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: Text(
                  'Invite ${contact.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ctx.text.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  2,
                  Space.lg,
                  Space.sm,
                ),
                child: Text(
                  contact.number,
                  style: TextStyle(color: ctx.colors.muted),
                ),
              ),
              ListTile(
                leading: const Text('💬', style: TextStyle(fontSize: 24)),
                title: const Text('Send on WhatsApp'),
                onTap: () =>
                    open(ContactInvite.whatsappUri(contact.number, text)),
              ),
              ListTile(
                leading: const Icon(Icons.sms_rounded),
                title: const Text('Send a text message'),
                onTap: () => open(ContactInvite.smsUri(contact.number, text)),
              ),
            ],
          ),
        ),
      );
    },
  );
}
