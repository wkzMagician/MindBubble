import 'dart:async';

import 'package:dartloom_sync/dartloom_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../services/sync_service.dart'
    show syncServiceProvider, syncSnapshotProvider;

/// Local notes remain interactive while Dartloom synchronizes in the background.
class SyncStatusOverlay extends ConsumerStatefulWidget {
  const SyncStatusOverlay({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SyncStatusOverlay> createState() => _SyncStatusOverlayState();
}

class _SyncStatusOverlayState extends ConsumerState<SyncStatusOverlay> {
  Object? _error;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadConfiguration());
  }

  Future<void> _loadConfiguration() async {
    try {
      // SyncCoordinator already owns startup/profile-activation triggers.
      await ref.read(syncServiceProvider).loadConfig();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() {
      _retrying = true;
      _error = null;
    });
    try {
      await ref.read(syncServiceProvider).syncNow();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(syncSnapshotProvider).valueOrNull;
    final phase = snapshot?.phase;
    final error = phase == SyncPhase.syncing || phase == SyncPhase.succeeded
        ? null
        : snapshot?.lastReport?.failure?.message ?? _error;
    return Stack(
      children: [
        widget.child,
        if (error != null)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(context.l10n.initialSyncFailed('$error')),
                      ),
                      TextButton(
                        onPressed: _retrying ? null : _retry,
                        child: Text(context.l10n.retry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
