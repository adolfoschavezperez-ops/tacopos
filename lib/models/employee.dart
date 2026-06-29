import 'package:cloud_firestore/cloud_firestore.dart';

class Employee {
  const Employee({required this.id, required this.name, required this.active});

  final String id;
  final String name;
  final bool active;

  factory Employee.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return Employee(
      id: doc.id,
      name: data['name'] as String? ?? doc.id,
      active: data['active'] as bool? ?? true,
    );
  }
}
