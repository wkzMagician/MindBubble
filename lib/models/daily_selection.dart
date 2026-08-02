class DailySelection {
  const DailySelection({
    required this.date,
    required this.bubbleIds,
    required this.generatedAt,
  });

  final String date;
  final List<String> bubbleIds;
  final DateTime generatedAt;
}
