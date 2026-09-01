import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/upnext_history_provider.dart';
import '../../services/tmdb_service.dart';
import '../../widgets/async_error.dart';

/// "Recently aired" — episodes of tracked shows that became available in
/// the last [kUpNextHistoryDays] days, grouped by day. Companion to the
/// Home "Up Next" row: that row only looks forward (+ a 1-day grace), so
/// a household that skips a few days would otherwise never see what
/// dropped while they were away.
class UpNextHistoryScreen extends ConsumerWidget {
  const UpNextHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(upNextHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Recently aired')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(upNextHistoryProvider),
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nothing has aired for your shows in the last 14 days.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            );
          }
          final groups = groupHistoryByDay(entries);
          final today = DateTime.now();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(upNextHistoryProvider.future),
            child: ListView.builder(
              itemCount: groups.length,
              itemBuilder: (context, i) {
                final group = groups[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        historyDayLabel(group.key, today),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    for (final e in group.value) _HistoryTile(entry: e),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final UpNextHistoryEntry entry;
  const _HistoryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final poster = TmdbService.imageUrl(entry.showPosterPath, size: 'w92');
    final epLabel = 'S${entry.season.toString().padLeft(2, '0')}'
        'E${entry.number.toString().padLeft(2, '0')}';
    final episodeName = entry.episodeName;
    final subtitle = (episodeName == null || episodeName.isEmpty)
        ? epLabel
        : '$epLabel · $episodeName';
    final local = entry.availableAt.toLocal();
    final trailing = entry.hasAirTime
        ? '~${local.hour.toString().padLeft(2, '0')}:'
            '${local.minute.toString().padLeft(2, '0')}'
        : '';
    return ListTile(
      dense: true,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: poster != null
            ? Image.network(
                poster,
                width: 40,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 40,
                  height: 60,
                  child: Icon(Icons.tv),
                ),
              )
            : const SizedBox(width: 40, height: 60, child: Icon(Icons.tv)),
      ),
      title: Text(entry.showTitle,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing.isEmpty
          ? null
          : Text(trailing,
              style: const TextStyle(fontSize: 12, color: Colors.white54)),
      onTap: () => context.push(
          '/title/tv/${entry.tmdbId}?season=${entry.season}&episode=${entry.number}'),
    );
  }
}
