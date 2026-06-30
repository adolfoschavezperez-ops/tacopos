import 'package:flutter/services.dart';

Future<String> exportCsvFile({
  required String fileName,
  required String content,
}) async {
  await Clipboard.setData(ClipboardData(text: content));
  return 'CSV copiado al portapapeles.';
}
