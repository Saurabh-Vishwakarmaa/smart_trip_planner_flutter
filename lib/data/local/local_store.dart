import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SavedTrip {
  final String id;
  final String title;
  final String startDate;
  final String endDate;
  final String json; // itinerary JSON

  SavedTrip({required this.id, required this.title, required this.startDate, required this.endDate, required this.json});

  Map<String, dynamic> toMap() => {'id': id, 'title': title, 'startDate': startDate, 'endDate': endDate, 'json': json};
  static SavedTrip fromMap(Map m) => SavedTrip(
        id: (m['id'] ?? '').toString(),
        title: (m['title'] ?? 'Trip').toString(),
        startDate: (m['startDate'] ?? '').toString(),
        endDate: (m['endDate'] ?? '').toString(),
        json: (m['json'] ?? '{}').toString(),
      );
}

class LocalStore {
  LocalStore._();
  static final instance = LocalStore._();
  static const _boxName = 'trips';

  Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox<Map>(_boxName);
  }

  Future<void> saveItinerary({required String title, required String startDate, required String endDate, required String json}) async {
    final id = const Uuid().v4();
    final box = Hive.box<Map>(_boxName);
    await box.put(id, {'id': id, 'title': title, 'startDate': startDate, 'endDate': endDate, 'json': json});
  }

  List<SavedTrip> getAll() {
    final box = Hive.box<Map>(_boxName);
    return box.keys.map((k) => SavedTrip.fromMap(box.get(k)!)).toList().reversed.toList();
  }

  Future<void> delete(String id) async {
    final box = Hive.box<Map>(_boxName);
    await box.delete(id);
  }
}

final savedTripsProvider = FutureProvider<List<SavedTrip>>((ref) async {
  return LocalStore.instance.getAll();
});