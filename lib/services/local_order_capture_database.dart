import 'package:sembast/sembast.dart';

import 'local_order_capture_database_stub.dart'
    if (dart.library.io) 'local_order_capture_database_io.dart'
    if (dart.library.js_interop) 'local_order_capture_database_web.dart'
    as platform;

Future<Database> openLocalOrderCaptureDatabase() =>
    platform.openLocalOrderCaptureDatabase();
