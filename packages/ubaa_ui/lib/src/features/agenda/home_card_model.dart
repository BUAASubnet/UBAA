final class HomeCardItem {
  const HomeCardItem({required this.title, required this.time, this.location});

  final String title;
  final String time;
  final String? location;
}

final class HomeCardWeekCell {
  const HomeCardWeekCell({
    required this.title,
    required this.time,
    required this.location,
    required this.color,
  });

  const HomeCardWeekCell.empty()
    : title = '',
      time = '',
      location = '',
      color = 0;

  final String title;
  final String time;
  final String location;
  final int color;

  bool get isEmpty => title.isEmpty;
}

final class HomeCardWeekRow {
  HomeCardWeekRow({required this.time, required List<HomeCardWeekCell> cells})
    : cells = List.unmodifiable(cells);

  final String time;
  final List<HomeCardWeekCell> cells;
}

final class HomeCardSnapshot {
  HomeCardSnapshot({
    required this.campusDay,
    required this.dateLabel,
    required this.signedIn,
    required List<HomeCardItem> agenda,
    required List<HomeCardItem> homework,
    required List<HomeCardItem> todo,
    this.weekLabel = '',
    this.todayWeekday = 1,
    List<HomeCardWeekRow> weekRows = const [],
  }) : agenda = List.unmodifiable(agenda),
       homework = List.unmodifiable(homework),
       todo = List.unmodifiable(todo),
       weekRows = List.unmodifiable(weekRows);

  final String campusDay;
  final String dateLabel;
  final bool signedIn;
  final List<HomeCardItem> agenda;
  final List<HomeCardItem> homework;
  final List<HomeCardItem> todo;
  final String weekLabel;
  final int todayWeekday;
  final List<HomeCardWeekRow> weekRows;
}
