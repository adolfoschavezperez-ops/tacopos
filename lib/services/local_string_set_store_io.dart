import 'dart:convert';
import 'dart:io';

class LocalStringSetStore {
  const LocalStringSetStore({required this.namespace});

  final String namespace;

  Future<Set<String>> readStringSet(String key) async {
    final data = await _readAll();
    final value = data[key];
    if (value is! List) return const <String>{};
    return value.whereType<String>().toSet();
  }

  Future<void> writeStringSet(String key, Set<String> values) async {
    final data = await _readAll();
    data[key] = values.toList()..sort();
    final file = await _file();
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  Future<Map<String, Object?>> _readAll() async {
    final file = await _file();
    if (!await file.exists()) return <String, Object?>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FormatException {
      return <String, Object?>{};
    } on IOException {
      return <String, Object?>{};
    }
    return <String, Object?>{};
  }

  Future<File> _file() async {
    final dir = await _storageDir();
    return File('${dir.path}${Platform.pathSeparator}$namespace.json');
  }

  Future<Directory> _storageDir() async {
    final androidFiles = Directory('/data/user/0/com.renova.tacopos/files');
    final dir = await androidFiles.exists()
        ? Directory('${androidFiles.path}/local_state')
        : Directory(
            '${Directory.systemTemp.path}${Platform.pathSeparator}com.renova.tacopos',
          );
    await dir.create(recursive: true);
    return dir;
  }
}
