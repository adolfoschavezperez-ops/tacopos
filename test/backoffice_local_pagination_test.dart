import 'package:flutter_test/flutter_test.dart';

import 'package:tacopos/core/backoffice/local_pagination.dart';

void main() {
  for (final count in const [0, 1, 49, 50, 51, 100, 101, 250]) {
    test(
      'preserva exactamente el orden y los datos para $count documentos',
      () {
        final allItems = List.generate(
          count,
          (index) => ('doc-$index', index + 0.25),
        );
        final pages = <List<(String, double)>>[];
        final totalPages = LocalPage.from(
          allItems: allItems,
          currentPage: 1,
        ).totalPages;
        final pagesToRead = totalPages == 0 ? 1 : totalPages;
        for (var pageNumber = 1; pageNumber <= pagesToRead; pageNumber++) {
          pages.add(
            LocalPage.from(allItems: allItems, currentPage: pageNumber).items,
          );
        }
        final flattened = pages.expand((page) => page).toList();
        expect(flattened, allItems);
        expect(flattened.map((item) => item.$1).toSet().length, count);
        expect(
          flattened.fold<double>(0, (sum, item) => sum + item.$2),
          allItems.fold<double>(0, (sum, item) => sum + item.$2),
        );
      },
    );
  }

  test('clamps a page after a refresh reduces the result set', () {
    final page = LocalPage.from(
      allItems: List.generate(101, (index) => index),
      currentPage: 5,
    );
    expect(page.currentPage, 3);
    expect(page.items, [100]);
    expect(page.hasNext, isFalse);
  });
}
