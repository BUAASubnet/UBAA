final class HomeCardItem {
  const HomeCardItem({required this.title, required this.time, this.location});

  final String title;
  final String time;
  final String? location;
}

final class HomeCardSnapshot {
  HomeCardSnapshot({
    required this.campusDay,
    required this.dateLabel,
    required this.signedIn,
    required List<HomeCardItem> agenda,
    required List<HomeCardItem> homework,
    required List<HomeCardItem> todo,
  }) : agenda = List.unmodifiable(agenda),
       homework = List.unmodifiable(homework),
       todo = List.unmodifiable(todo);

  final String campusDay;
  final String dateLabel;
  final bool signedIn;
  final List<HomeCardItem> agenda;
  final List<HomeCardItem> homework;
  final List<HomeCardItem> todo;
}
