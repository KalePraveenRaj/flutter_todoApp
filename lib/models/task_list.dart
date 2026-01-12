class TaskList {
  final String id;
  String name;
  bool isVisible;

  TaskList({
    required this.id,
    required this.name,
    this.isVisible = true, // ✅ IMPORTANT
  });
}
