extension HumanReadableDuration on Duration {
  String toHumanReadableString() {
    if (inSeconds < 60) {
      return '$inSeconds second${inSeconds != 1 ? 's' : ''}';
    } else if (inMinutes < 60) {
      final seconds = inSeconds % 60;
      return '${inMinutes} minute${inMinutes != 1 ? 's' : ''}' +
          (seconds > 0 ? ' $seconds second${seconds != 1 ? 's' : ''}' : '');
    } else if (inHours < 24) {
      final minutes = inMinutes % 60;
      return '${inHours} hour${inHours != 1 ? 's' : ''}' +
          (minutes > 0 ? ' ${minutes} minute${minutes != 1 ? 's' : ''}' : '');
    } else {
      final hours = inHours % 24;
      final days = inDays;
      return '$days day${days != 1 ? 's' : ''}' +
          (hours > 0 ? ' ${hours} hour${hours != 1 ? 's' : ''}' : '');
    }
  }
}
