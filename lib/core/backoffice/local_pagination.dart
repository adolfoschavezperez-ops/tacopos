/// A view over a complete in-memory result set. It never loads or filters data.
class LocalPage<T> {
  const LocalPage({
    required this.items,
    required this.currentPage,
    required this.totalPages,
    required this.hasPrevious,
    required this.hasNext,
  });

  static LocalPage<T> from<T>({
    required List<T> allItems,
    required int currentPage,
    int pageSize = 50,
  }) {
    if (pageSize <= 0) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Must be positive.');
    }
    final totalPages = allItems.isEmpty
        ? 0
        : (allItems.length + pageSize - 1) ~/ pageSize;
    final safePage = totalPages == 0 ? 1 : currentPage.clamp(1, totalPages);
    final start = totalPages == 0 ? 0 : (safePage - 1) * pageSize;
    final end = totalPages == 0
        ? 0
        : (start + pageSize).clamp(0, allItems.length);
    return LocalPage<T>(
      items: List<T>.unmodifiable(allItems.sublist(start, end)),
      currentPage: safePage,
      totalPages: totalPages,
      hasPrevious: safePage > 1,
      hasNext: totalPages > 0 && safePage < totalPages,
    );
  }

  final List<T> items;
  final int currentPage;
  final int totalPages;
  final bool hasPrevious;
  final bool hasNext;
}
