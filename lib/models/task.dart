import 'RepeatConfig.dart';

class Task {
  /// 🔑 Unique id for every task
  final String id;

  /// 📋 List this task belongs to
  final String listId;

  /// 👨‍👧 Parent task id (null = normal task)
  final String? parentId;

  /// 📝 Task data
  String title;
  bool isCompleted;
  bool isStarred;

  /// 🕒 Dates
  final DateTime createdAt;
  DateTime? dueDate;
  DateTime? starredAt;

  /// 🔁 Repeat / Reminder config
  RepeatConfig? repeatConfig;

  Task({
    String? id,
    required this.title,
    required this.listId,
    this.parentId,
    this.isCompleted = false,
    this.isStarred = false,
    DateTime? createdAt,
    this.dueDate,
    this.starredAt,
    this.repeatConfig, // ✅ FIXED: assign it properly
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       createdAt = createdAt ?? DateTime.now();
}
