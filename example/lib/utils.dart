import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class Utils {
  static Future<String> getFileUrl(String fileName) async {
    String path = '';
    if (kIsWeb) {
      path = 'assets';
    } else {
      final directory = await getApplicationDocumentsDirectory();
      path = directory.path;
    }
    return '$path/$fileName';
  }
}
