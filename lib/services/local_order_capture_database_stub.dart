import 'package:sembast/sembast_memory.dart';

Future<Database> openLocalOrderCaptureDatabase() =>
    databaseFactoryMemory.openDatabase('tacopos-local-order-captures');
