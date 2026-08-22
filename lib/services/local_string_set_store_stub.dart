class LocalStringSetStore {
  const LocalStringSetStore({required this.namespace});

  final String namespace;

  Future<Set<String>> readStringSet(String key) async => const <String>{};

  Future<void> writeStringSet(String key, Set<String> values) async {}
}
