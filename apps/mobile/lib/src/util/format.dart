String relativeTime(DateTime? time) {
  if (time == null) return '';
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final local = time.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String elapsedLabel(DateTime startedAt, {DateTime? endedAt}) {
  final end = endedAt ?? DateTime.now();
  final seconds = end.difference(startedAt).inSeconds;
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return '${hours}h ${rest}m';
}

String shortenPath(String path, {int maxLength = 48}) {
  if (path.length <= maxLength) return path;
  final parts = path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty);
  if (parts.isEmpty) return path;
  var result = parts.last;
  for (final part in parts.toList().reversed.skip(1)) {
    final next = '$part/$result';
    if (next.length + 2 > maxLength) break;
    result = next;
  }
  return '…/$result';
}

String fileTimestamp(DateTime? time) {
  if (time == null) return '';
  final local = time.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
