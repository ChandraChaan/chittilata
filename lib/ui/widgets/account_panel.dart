import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/services/account.dart';
import '../../core/theme/app_theme.dart';
import 'common.dart';

/// Optional Google sign-in: keeps a player's profile, level, badges and
/// match history across phones. Playing as a guest works exactly as before.
class AccountPanel extends StatelessWidget {
  const AccountPanel({super.key, this.deleteForGuests = true});

  /// Settings always offers deleting; the profile only once signed in.
  final bool deleteForGuests;

  @override
  Widget build(BuildContext context) {
    final account = Services.of(context).account;
    if (account == null) return const SizedBox.shrink();
    final c = context.colors;
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final google = account.google;
        final busy = account.busy;
        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    google == null
                        ? Icons.cloud_off_rounded
                        : Icons.cloud_done_rounded,
                    color: google == null ? c.muted : c.marigold,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      google == null ? 'Playing as a guest' : 'Signed in',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(
                google == null
                    ? 'Optional: sign in with Google to keep your level, '
                          'badges and match history on any phone, even after '
                          'reinstalling.'
                    : '${google.email ?? google.name ?? 'Google account'}\n'
                          'Your profile, level, badges and match history are '
                          'saved to your account.',
                style: TextStyle(color: c.muted, fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: Space.md),
              if (google == null)
                BigButton(
                  label: 'Sign in with Google',
                  icon: Icons.login_rounded,
                  busy: busy,
                  onPressed: busy ? null : () => signInWithGoogle(context),
                )
              else
                BigButton(
                  label: 'Sign out',
                  icon: Icons.logout_rounded,
                  secondary: true,
                  busy: busy,
                  onPressed: busy ? null : () => _signOut(context),
                ),
              if (google != null || deleteForGuests) ...[
                const SizedBox(height: Space.xs),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: c.kumkum),
                  onPressed: busy ? null : () => _delete(context),
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('Delete my account and data'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

Future<void> _guard(BuildContext context, Future<void> Function() f) async {
  try {
    await f();
  } on AccountException catch (e) {
    if (context.mounted) showGameSnack(context, e.message);
  } catch (_) {
    if (context.mounted) {
      showGameSnack(context, 'Something went wrong. Please try again.');
    }
  }
}

/// Links this phone's player to Google, or (asking first) switches to the
/// player that Google account already has.
Future<void> signInWithGoogle(
  BuildContext context,
) => _guard(context, () async {
  final account = Services.read(context).account!;
  final result = await account.signInWithGoogle();
  if (!context.mounted) return;
  switch (result) {
    case SignInResult.cancelled:
      return;
    case SignInResult.linked:
      showGameSnack(context, 'Signed in. Your progress is saved.');
    case SignInResult.needsSwitch:
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Use your saved profile?'),
          content: const Text(
            'This Google account already has a ChitPlay profile. Switch to it '
            'and the stats, badges and history from this phone are added to '
            'it.\n\nRooms and groups you joined on this phone as a guest will '
            'be left.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (ok != true) {
        await account.cancelSwitch();
        return;
      }
      await account.switchToExisting();
      if (context.mounted) {
        showGameSnack(context, 'Welcome back! Your profiles are combined.');
      }
  }
});

Future<void> _signOut(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out?'),
      content: const Text(
        'Your profile, rooms and groups stay with your Google account. This '
        'phone plays as a new guest until you sign in again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await _guard(context, () async {
    await Services.read(context).account!.signOut();
    if (context.mounted) showGameSnack(context, 'Signed out.');
  });
}

Future<void> _delete(BuildContext context) async {
  final c = context.colors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete your account and data?'),
      content: const Text(
        'This deletes your sign-in and your saved profile (name, avatar, '
        'stats, badges and match history), takes you out of your rooms and '
        'groups, and clears your profile from this phone.\n\n'
        'This can\'t be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.kumkum),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await _guard(context, () async {
    await Services.read(context).account!.deleteAccount();
    if (context.mounted) {
      showGameSnack(context, 'Your account and data were deleted.');
    }
  });
}
