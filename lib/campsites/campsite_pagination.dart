typedef PageResult<T> = ({List<T> items, bool hasNext});
typedef PageFetcher<T> = Future<PageResult<T>> Function(int page);

Future<List<T>> aggregateAllPages<T>(
  PageFetcher<T> fetchPage, {
  int maxPages = 10,
}) async {
  final all = <T>[];
  for (var page = 0; page < maxPages; page++) {
    final result = await fetchPage(page);
    all.addAll(result.items);
    if (!result.hasNext) break;
  }
  return all;
}
