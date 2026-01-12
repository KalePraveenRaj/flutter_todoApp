import 'package:flutter/material.dart';

class RepeatConfig {
  int interval; // 1, 2, 3...
  String unit; // day | week | month | year
  TimeOfDay time; // 11:30 PM
  DateTime startDate; // January 11
  String ends; // never | on | after
  DateTime? endDate; // February 10
  int? occurrences; // 30 times

  RepeatConfig({
    required this.interval,
    required this.unit,
    required this.time,
    required this.startDate,
    this.ends = 'never',
    this.endDate,
    this.occurrences,
  });
}
