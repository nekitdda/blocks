import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:youmuz/src/features/auth/providers/auth_provider.dart';
import 'package:youmuz/src/rust/api/content.dart' as rust;
import 'package:youmuz/src/rust/api/models.dart';
import 'package:youmuz/src/ui/ui.dart';

/// Keeps a [GLoader]/[GEmptyState], which centre in all the space they get,
/// at its natural height inside the dialog.
Widget _dialogFit(Widget child) =>
    Column(mainAxisSize: MainAxisSize.min, children: [child]);

class TrackDetailsDialog extends StatefulWidget {
  final String trackId;

  const TrackDetailsDialog({required this.trackId, super.key});

  @override
  State<TrackDetailsDialog> createState() => _TrackDetailsDialogState();

  static void show(BuildContext context, String trackId) {
    unawaited(
      showGDialog<void>(
        context,
        builder: (context) => TrackDetailsDialog(trackId: trackId),
      ),
    );
  }
}

class _TrackDetailsDialogState extends State<TrackDetailsDialog> {
  late final FutureSignal<TrackDetailsDto?> _detailsAsync;

  @override
  void initState() {
    super.initState();
    _detailsAsync = futureSignal(() async {
      final ctx = appContextSignal.value;
      if (ctx == null) return null;
      return await rust.getTrackDetails(ctx: ctx, trackId: widget.trackId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final result = _detailsAsync.value;
        return GDialog(
          title: 'О треке',
          width: 500,
          content: result.map(
            loading: () => _dialogFit(const GLoader()),
            // No session yet: the signal refetches once it appears.
            data: (details) => details == null
                ? _dialogFit(const GLoader())
                : _buildDetails(details),
            error: (Object e, _) => _dialogFit(
              GEmptyState(
                icon: LucideIcons.circleAlert,
                title: 'Не удалось загрузить сведения',
                message: e.toString(),
                compact: true,
              ),
            ),
          ),
          actions: [
            GButton(
              label: 'Закрыть',
              variant: GButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  bool _isValid(String? value) {
    if (value == null || value.isEmpty || value.trim() == '-') return false;
    return true;
  }

  Widget _buildDetails(TrackDetailsDto details) {
    final music = details.musicAuthors.where((a) => a != '-').toList();
    final lyrics = details.lyricsAuthors.where((a) => a != '-').toList();
    final platforms = details.sourcePlatforms.where((a) => a != '-').toList();

    final rows = <(String, String)>[
      if (_isValid(details.title)) ('Название', details.title),
      ('Исполнитель', details.artists.map((a) => a.name).join(', ')),
      if (_isValid(details.album)) ('Альбом', details.album!),
      if (_isValid(details.label)) ('Лейбл', details.label!),
      if (music.isNotEmpty) ('Автор музыки', music.join(', ')),
      if (lyrics.isNotEmpty) ('Автор текста', lyrics.join(', ')),
      if (platforms.isNotEmpty) ('Источник фонограммы', platforms.join(', ')),
    ];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const GDivider(),
            _InfoRow(label: rows[i].$1, value: rows[i].$2),
          ],
        ],
      ),
    );
  }
}

/// Label/value row; the label moves above the value when space is tight.
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final labelText = Text(
      label,
      style: GText.sm(color: GColors.mutedForeground),
    );
    final valueText = Text(value, style: GText.sm());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 360) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 2), valueText],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 156, child: labelText),
              const SizedBox(width: 16),
              Expanded(child: valueText),
            ],
          );
        },
      ),
    );
  }
}
