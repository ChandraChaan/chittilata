import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/services/app_updater.dart';
import '../../core/services/feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../data/app_config.dart';
import 'common.dart';

/// Sits above every screen. When the developer raises `minBuild` in
/// `config/app`, older installs see a full-screen "Update required" page
/// they cannot get past; when only `latestBuild` is newer, a small card
/// offers the update and can be dismissed.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  StreamSubscription<AppConfig>? _sub;
  AppConfig _config = AppConfig.none;
  int? _build;
  bool _updating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sub != null) return;
    _sub = Services.of(context).repo.watchAppConfig().listen((c) {
      if (mounted) setState(() => _config = c);
    }, onError: (_) {});
    AppUpdater.currentBuild().then((b) {
      if (mounted) setState(() => _build = b);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _update() async {
    setState(() => _updating = true);
    try {
      await AppUpdater.update(url: _config.updateUrl);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final build = _build;
    final prefs = Services.of(context).prefs;
    final forced = build != null && build < _config.minBuild;
    final optional =
        !forced &&
        build != null &&
        build < _config.latestBuild &&
        prefs.dismissedUpdate < _config.latestBuild;
    return Stack(
      children: [
        // Blocked screens stay mounted (a running game keeps its state) but
        // can't be touched or read by screen readers.
        ExcludeSemantics(
          excluding: forced,
          child: AbsorbPointer(absorbing: forced, child: widget.child),
        ),
        if (forced)
          Positioned.fill(
            child: _UpdateRequired(
              message: _config.message,
              busy: _updating,
              onUpdate: _update,
            ),
          )
        else if (optional)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: _UpdateCard(
                message: _config.message,
                busy: _updating,
                onUpdate: _update,
                onLater: () {
                  Services.read(context).feedback.ui(Sfx.close);
                  prefs.dismissedUpdate = _config.latestBuild;
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _UpdateRequired extends StatelessWidget {
  const _UpdateRequired({
    required this.message,
    required this.busy,
    required this.onUpdate,
  });
  final String? message;
  final bool busy;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      child: GameBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Space.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.system_update_rounded,
                    size: 84,
                    color: c.marigold,
                  ),
                  const SizedBox(height: Space.lg),
                  GoldText(
                    'Update required',
                    textAlign: TextAlign.center,
                    style: context.text.headlineMedium,
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    message ??
                        'A new version of Chittilata is out. Update to keep '
                            'playing with your friends.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, height: 1.4, fontSize: 16),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    'Your name and match history stay on this phone.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted, fontSize: 13),
                  ),
                  const SizedBox(height: Space.xxl),
                  BigButton(
                    label: 'Update now',
                    icon: Icons.download_rounded,
                    busy: busy,
                    onPressed: onUpdate,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.message,
    required this.busy,
    required this.onUpdate,
    required this.onLater,
  });
  final String? message;
  final bool busy;
  final VoidCallback onUpdate;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Material(
            color: Colors.transparent,
            child: Panel(
              color: c.surfaceHigh,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: c.marigold),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'New version available',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            if (message != null)
                              Text(
                                message!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.muted, fontSize: 13),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: Space.sm,
                    children: [
                      TextButton(
                        onPressed: onLater,
                        child: const Text('Later'),
                      ),
                      FilledButton(
                        onPressed: busy ? null : onUpdate,
                        child: const Text('Update'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
