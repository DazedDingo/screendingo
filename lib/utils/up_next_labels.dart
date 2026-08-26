import '../providers/upnext_provider.dart';

/// Shared "when" label formatters for Up Next rows — Home marquee/strip,
/// the home-screen widget, and the Profile health line all render off
/// the same [UpNextEpisode], so the wording only needs to live once.
///
/// `HH:mm` is always local time, 24h, zero-padded — Trakt's `first_aired`
/// is real UTC broadcast time, but the household cares what it reads on
/// their own clock.
String _hhmm(DateTime dt) {
  final local = dt.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Home row / widget label — title case, e.g. "Today ~20:00", "Out now",
/// "Tomorrow", "In 3d".
String upNextRelativeLabel(UpNextEpisode e, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = e.daysUntilAir;
  if (d == 0) {
    if (!e.hasAirTime) return 'Out today';
    return n.isBefore(e.availableAt) ? 'Today ~${_hhmm(e.availableAt)}' : 'Out now';
  }
  if (d == 1) {
    return e.hasAirTime ? 'Tomorrow ~${_hhmm(e.availableAt)}' : 'Tomorrow';
  }
  if (d == -1) return 'Aired yesterday';
  if (d < -1) return 'Just aired';
  return 'In ${d}d';
}

/// Profile "Up next" health-line variant — lower-case, e.g.
/// "today ~20:00", "out now", "tomorrow", "in 3d".
String upNextRelativeLabelCompact(UpNextEpisode e, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = e.daysUntilAir;
  if (d == 0) {
    if (!e.hasAirTime) return 'today';
    return n.isBefore(e.availableAt) ? 'today ~${_hhmm(e.availableAt)}' : 'out now';
  }
  if (d == 1) {
    return e.hasAirTime ? 'tomorrow ~${_hhmm(e.availableAt)}' : 'tomorrow';
  }
  if (d < 0) return 'just aired';
  return 'in ${d}d';
}
