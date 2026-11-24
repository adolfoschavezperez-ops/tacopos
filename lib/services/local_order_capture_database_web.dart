import 'package:sembast_web/sembast_web.dart';

Future<Database> openLocalOrderCaptureDatabase() =>
    databaseFactoryWeb.openDatabase('tacopos-local-order-captures-v1');
