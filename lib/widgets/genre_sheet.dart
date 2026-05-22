import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/genre_filter_provider.dart';
import '../providers/mode_provider.dart';

/// Full-list multi-select over every TMDB genre (movie + TV union, deduped
/// and alphabetised). Writes land on `modeGenreProvider` immediately so the
/// home-screen filter reacts while the sheet is still open. "Done" dismisses,
/// "Clear all" resets the mode's set to empty.
class GenreSheet extends ConsumerWidget {
  final ViewMode mode;
  const GenreSheet({super.key, required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allGenresProvider);
    final selected = ref.watch(selectedGenresProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Filter by genre',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: selected.isEmpty
                      ? null
                      : () => ref.read(modeGenreProvider.notifier).clear(mode),
                  child: const Text('Clear all',
                      style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final g in all)
                      FilterChip(
                        label: Text(g),
                        selected: selected.contains(g),
                        onSelected: (_) => ref
                            .read(modeGenreProvider.notifier)
                            .toggle(mode, g),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
