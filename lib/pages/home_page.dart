import 'package:flutter/material.dart';
import 'package:todo_app/models/task_list.dart';
import '../models/task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../models/RepeatConfig.dart';

enum ListSortType { myOrder, date, deadline, starred, title }

enum TaskFilter { all, starred }

final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

bool _isAllTasksView = true;

class HomePage extends StatefulWidget {
  final ThemeMode currentTheme;
  final Function(ThemeMode) onThemeChanged;

  const HomePage({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FocusNode _inlineFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    _initializeNotifications();

    _inlineFocusNode.addListener(() {
      if (!_inlineFocusNode.hasFocus && _inlineTitleCtrl.text.trim().isEmpty) {
        setState(() {
          _editingListId = null;
          _editingParentTask = null;
          _editingInsertIndex = null;
          _resetInlineEditor();
        });
      }
    });
  }

  Future<void> _initializeNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(android: android),
    );
  }

  Future<void> _scheduleTaskNotification(Task task) async {
    if (task.dueDate == null) return;

    tz.initializeTimeZones();

    final baseDate = task.dueDate!;
    final repeat = task.repeatConfig;

    tz.TZDateTime scheduledDate = tz.TZDateTime.from(baseDate, tz.local);

    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) return;

    // 🔁 REPEATING TASK
    if (repeat != null) {
      DateTimeComponents? components;

      switch (repeat.unit) {
        case 'day':
          components = DateTimeComponents.time;
          break;
        case 'week':
          components = DateTimeComponents.dayOfWeekAndTime;
          break;
        case 'month':
          components = DateTimeComponents.dayOfMonthAndTime;
          break;
        case 'year':
          components = DateTimeComponents.dateAndTime;
          break;
      }

      await flutterLocalNotificationsPlugin.zonedSchedule(
        task.hashCode,
        'Task reminder',
        task.title,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'tasks_channel',
            'Tasks',
            channelDescription: 'Task reminders',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: components, // ✅ REPEAT
      );
    } else {
      // ⏰ ONE-TIME
      await flutterLocalNotificationsPlugin.zonedSchedule(
        task.hashCode,
        'Task reminder',
        task.title,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'tasks_channel',
            'Tasks',
            channelDescription: 'Task reminders',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> _cancelTaskNotification(Task task) async {
    await flutterLocalNotificationsPlugin.cancel(task.hashCode);
  }

  final Map<Task, bool> _hoveredTasks = {};

  bool _isSidebarOpen = true; // Google Tasks default
  final Map<String, bool> _completedExpanded = {};
  bool _isCompletedExpanded(String listId) {
    return _completedExpanded[listId] ?? false;
  }

  bool _isMenuOpen = false;
  Task? _editingParentTask; // 👈 track subtask parent
  int? _editingInsertIndex; // 👈 where to insert

  final Map<String, ListSortType> _listSortType = {};

  String? _editingListId;
  final _inlineTitleCtrl = TextEditingController();
  final _inlineDetailsCtrl = TextEditingController();
  DateTime? _inlineDueDate;
  bool get _hasInlineDate => _inlineDueDate != null;
  RepeatConfig? _customRepeat;

  bool get _isToday =>
      _inlineDueDate != null &&
      DateUtils.isSameDay(_inlineDueDate, DateTime.now());

  bool get _isTomorrow =>
      _inlineDueDate != null &&
      DateUtils.isSameDay(
        _inlineDueDate,
        DateTime.now().add(const Duration(days: 1)),
      );

  String get _inlineDateLabel {
    if (_isToday) return 'Today';
    if (_isTomorrow) return 'Tomorrow';
    return '${_inlineDueDate!.day}/${_inlineDueDate!.month}/${_inlineDueDate!.year}';
  }

  void _resetInlineEditor() {
    _inlineTitleCtrl.clear();
    _inlineDetailsCtrl.clear();
    _inlineDueDate = null;
  }

  void _saveInlineTask(String listId) {
    final title = _inlineTitleCtrl.text.trim();
    if (title.isEmpty) return;

    // ✅ Create ONE task instance
    final task = Task(
      title: title,
      listId: listId,
      parentId: _editingParentTask?.id,
      dueDate: _inlineDueDate,
      repeatConfig: _customRepeat, // ✅ ADD THIS
      isStarred: _currentFilter == TaskFilter.starred,
      starredAt: _currentFilter == TaskFilter.starred ? DateTime.now() : null,
    );

    setState(() {
      if (_editingInsertIndex != null) {
        // 🔹 SUBTASK
        tasks.insert(_editingInsertIndex!, task);
      } else {
        // 🔹 NORMAL TASK
        final index = tasks.indexWhere((t) => t.listId == listId);
        index == -1 ? tasks.add(task) : tasks.insert(index, task);
      }

      // ✅ Reset editor
      _editingListId = null;
      _editingParentTask = null;
      _editingInsertIndex = null;
      _inlineTitleCtrl.clear();
      _inlineDetailsCtrl.clear();
      _inlineDueDate = null;
    });

    // 🔔 Schedule notification ONCE
    _scheduleTaskNotification(task);
  }

  Map<TaskList, List<Task>> _groupTasksByList(List<Task> tasks) {
    final Map<TaskList, List<Task>> map = {};

    for (final list in lists) {
      if (!list.isVisible) continue; // keep this

      final listTasks = tasks.where((t) => t.listId == list.id).toList();

      map[list] = listTasks; // ✅ SHOW EMPTY LIST CARD
    }

    return map;
  }

  bool _listsExpanded = true;
  bool _showMyTasks = true;

  final List<Task> tasks = [];
  TaskFilter _currentFilter = TaskFilter.all;

  final List<TaskList> lists = [TaskList(id: 'default', name: 'My Tasks')];

  String _selectedListId = 'default';

  void toggleStar(Task task) {
    setState(() {
      task.isStarred = !task.isStarred;
      task.starredAt = task.isStarred ? DateTime.now() : null;
    });
  }

  void _moveTaskToList(Task task, String newListId) {
    setState(() {
      final index = tasks.indexOf(task);
      if (index == -1) return;

      tasks[index] = Task(
        title: task.title,
        listId: newListId,
        dueDate: task.dueDate,
        isCompleted: task.isCompleted,
        isStarred: task.isStarred,
        starredAt: task.starredAt,
        createdAt: task.createdAt,
      );
    });
  }

  // ➕ Add task
  void addTask(String title) {
    setState(() {
      final newTask = Task(
        title: title,
        listId: _selectedListId,
        isStarred: _currentFilter == TaskFilter.starred,
        starredAt: _currentFilter == TaskFilter.starred ? DateTime.now() : null,
      );

      // insert task at top of that list
      final index = tasks.indexWhere((t) => t.listId == _selectedListId);
      if (index == -1) {
        tasks.add(newTask);
      } else {
        tasks.insert(index, newTask);
      }
    });
  }

  // ✅ Toggle completion
  void toggleTask(Task task) {
    setState(() {
      task.isCompleted = !task.isCompleted;
    });
  }

  // 🗑 Delete task
  void deleteTask(Task task) {
    _cancelTaskNotification(task);

    setState(() {
      tasks.remove(task);
    });
  }

  Widget _buildHeader(BuildContext context) {
    if (_currentFilter == TaskFilter.starred) {
      return const Text(
        'Starred Tasks',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      );
    }

    if (_isAllTasksView) {
      return const Text(
        'All Tasks',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      );
    }

    final listName = lists.firstWhere((l) => l.id == _selectedListId).name;

    return Text(
      listName,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Task> visibleTasks = tasks.where((task) {
      final list = lists.firstWhere((l) => l.id == task.listId);

      // respect list visibility
      if (!list.isVisible) return false;

      // starred filter
      if (_currentFilter == TaskFilter.starred && !task.isStarred) {
        return false;
      }

      // ⛔ REMOVE listId filtering here
      return true;
    }).toList();

    //final sortedTasks = _sortTasks(visibleTasks, _selectedListId);

    final pending = visibleTasks.where((t) => !t.isCompleted).toList();
    final completed = visibleTasks.where((t) => t.isCompleted).toList();

    final bgColor = Theme.of(context).colorScheme.surface;

    return Scaffold(
      backgroundColor: bgColor,

      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            setState(() {
              _isSidebarOpen = !_isSidebarOpen;
            });
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/symbol.JPG',
              height: 28,
              width: 28,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            const Text(
              'Tasks',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ],
        ),

        actions: [
          IconButton(
            tooltip: 'Toggle theme',
            icon: Icon(
              widget.currentTheme == ThemeMode.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: () {
              widget.onThemeChanged(
                widget.currentTheme == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark,
              );
            },
          ),
        ],
      ),

      // ☰ GOOGLE TASKS–STYLE DRAWER
      //drawer: _buildDrawer(context),

      // 🔁 Task list
      body: Row(
        children: [
          // 🟦 SIDEBAR (PART OF PAGE)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: _isSidebarOpen ? 280 : 0,
            curve: Curves.easeInOut,
            color: bgColor, // 👈 SAME AS PAGE
            child: _isSidebarOpen ? _buildDrawer(context) : null,
          ),

          // 🟩 MAIN CONTENT
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: lists.isEmpty
                  ? _buildEmptyState(context)
                  : _buildListsView(context, visibleTasks),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListsView(BuildContext context, List<Task> visibleTasks) {
    final grouped = _groupTasksByList(visibleTasks);

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: grouped.length,
      separatorBuilder: (_, __) => const SizedBox(width: 16),
      itemBuilder: (context, index) {
        final list = grouped.keys.elementAt(index);

        // ✅ SORT PER LIST (THIS IS THE FIX)
        final listTasks = _sortTasks(grouped[list]!, list.id);

        final parentTasks = listTasks
            .where((t) => t.parentId == null && !t.isCompleted)
            .toList();

        final completed = listTasks.where((t) => t.isCompleted).toList();

        final bool hasTasks = listTasks.isNotEmpty;
        final bool allCompleted =
            hasTasks && parentTasks.isEmpty && completed.isNotEmpty;
        // 🔢 number of visible rows
        final int visibleItems =
            parentTasks.length +
            (_isCompletedExpanded(list.id) ? completed.length : 0);

        // 📏 dynamic card height
        const double minHeight = 120;
        const double maxHeight = 320;
        const double rowHeight = 56;

        final double cardHeight = (minHeight + visibleItems * rowHeight).clamp(
          minHeight,
          maxHeight,
        );

        return Align(
          alignment: Alignment.topCenter, // ✅ allows vertical shrink/grow
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: double.infinity),
            child: SizedBox(
              width: 320,
              child: Card(
                elevation: 0,
                color: Theme.of(context).brightness == Brightness.light
                    ? Colors.white
                    : Theme.of(context).colorScheme.surface,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Colors.black.withOpacity(0.2),
                    width: 0.8,
                  ),
                ),

                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    if (_isMenuOpen) return;

                    // ✅ If editor is open but empty → close
                    if (_editingListId == list.id &&
                        _inlineTitleCtrl.text.trim().isEmpty) {
                      setState(() {
                        _editingListId = null;
                        _editingParentTask = null;
                        _editingInsertIndex = null;
                        _resetInlineEditor();
                      });
                    }
                    // ✅ If editor has text → save
                    else if (_editingListId == list.id) {
                      _saveInlineTask(list.id);
                    }

                    FocusScope.of(context).unfocus();
                  },

                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min, // 🔥 REQUIRED
                      children: [
                        // ───────── HEADER ─────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              list.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, size: 20),
                              onOpened: () =>
                                  setState(() => _isMenuOpen = true),
                              onCanceled: () =>
                                  setState(() => _isMenuOpen = false),
                              onSelected: (value) {
                                setState(() => _isMenuOpen = false);
                                _handleListMenuAction(value, list);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  enabled: false,
                                  child: Text(
                                    'Sort by',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'sort_my_order',
                                  child: Text('My order'),
                                ),
                                const PopupMenuItem(
                                  value: 'sort_date',
                                  child: Text('Date'),
                                ),
                                const PopupMenuItem(
                                  value: 'sort_deadline',
                                  child: Text('Deadline'),
                                ),
                                const PopupMenuItem(
                                  value: 'sort_starred',
                                  child: Text('Starred recently'),
                                ),
                                const PopupMenuItem(
                                  value: 'sort_title',
                                  child: Text('Title'),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename list'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  enabled: list.id != 'default',
                                  child: const Text('Delete list'),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: 'delete_completed',
                                  child: Text('Delete all completed tasks'),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // ───────── ADD TASK ─────────
                        InkWell(
                          onTap: () {
                            setState(() {
                              // ✅ IF editor is already open AND has text → SAVE FIRST
                              if (_editingListId == list.id &&
                                  _inlineTitleCtrl.text.trim().isNotEmpty) {
                                _saveInlineTask(list.id);

                                // 🔁 reopen editor for next task (Google Tasks behavior)
                                _editingListId = list.id;
                                _editingParentTask = null;
                                _editingInsertIndex = null;
                                _resetInlineEditor();
                                return;
                              }

                              // ✅ OTHERWISE just open editor
                              _editingListId = list.id;
                              _editingParentTask = null;
                              _editingInsertIndex = null;
                              _resetInlineEditor();
                            });
                          },

                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.add,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Add task',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (_editingListId == list.id &&
                            _editingParentTask == null)
                          _buildInlineEditor(list.id),

                        const SizedBox(height: 8),

                        // ───────── TASK AREA (DYNAMIC HEIGHT) ─────────
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: maxHeight,
                              minHeight:
                                  parentTasks.isEmpty &&
                                      completed.isEmpty &&
                                      _editingListId != list.id
                                  ? 60
                                  : 0,
                            ),
                            child: SingleChildScrollView(
                              physics:
                                  (parentTasks.length +
                                              (_isCompletedExpanded(list.id)
                                                  ? completed.length
                                                  : 0)) *
                                          rowHeight >=
                                      maxHeight
                                  ? const BouncingScrollPhysics()
                                  : const NeverScrollableScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // PENDING + SUBTASKS
                                  for (final task in parentTasks) ...[
                                    _buildTaskTile(task),
                                    ...listTasks
                                        .where((t) => t.parentId == task.id)
                                        .map(
                                          (sub) => Padding(
                                            padding: const EdgeInsets.only(
                                              left: 32,
                                            ),
                                            child: _buildTaskTile(
                                              sub,
                                              isSubtask: true,
                                            ),
                                          ),
                                        ),
                                    // 👇 THIS IS CRITICAL
                                    if (_editingParentTask == task)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          left: 32,
                                        ),
                                        child: _buildInlineEditor(list.id),
                                      ),
                                  ],

                                  // ALL COMPLETED MESSAGE
                                  if (allCompleted && _editingListId != list.id)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: Center(
                                        child: Column(
                                          children: const [
                                            Icon(
                                              Icons.emoji_events_outlined,
                                              size: 32,
                                            ),
                                            SizedBox(height: 8),
                                            Text(
                                              'All tasks completed',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text('Nice work 🎉'),
                                          ],
                                        ),
                                      ),
                                    ),

                                  // COMPLETED
                                  if (completed.isNotEmpty) ...[
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          _completedExpanded[list.id] =
                                              !_isCompletedExpanded(list.id);
                                        });
                                      },
                                      child: Row(
                                        children: [
                                          Icon(
                                            _isCompletedExpanded(list.id)
                                                ? Icons.expand_less
                                                : Icons.expand_more,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Completed (${completed.length})',
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_isCompletedExpanded(list.id))
                                      ...completed.map(_buildTaskTile),
                                  ],

                                  // EMPTY STATE
                                  if (parentTasks.isEmpty &&
                                      completed.isEmpty &&
                                      _editingListId != list.id)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 24),
                                      child: Text(
                                        'No tasks',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outline,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInlineEditor(String listId) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 📝 TITLE
            TextField(
              controller: _inlineTitleCtrl,
              focusNode: _inlineFocusNode, // ✅ ONLY HERE
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _saveInlineTask(listId),
            ),

            // 🧾 DETAILS
            TextField(
              controller: _inlineDetailsCtrl,
              decoration: const InputDecoration(
                hintText: 'Details',
                border: InputBorder.none,
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 8),

            // 📅 DATE OPTIONS
            Row(
              children: [
                if (!_hasInlineDate) ...[
                  TextButton(
                    onPressed: () =>
                        setState(() => _inlineDueDate = DateTime.now()),
                    child: const Text('Today'),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => _inlineDueDate = DateTime.now().add(
                        const Duration(days: 1),
                      ),
                    ),
                    child: const Text('Tomorrow'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.calendar_today_outlined),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() => _inlineDueDate = date);
                      }
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No tasks yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a task to get started',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList(List<Task> pendingTasks, List<Task> completedTasks) {
    return ReorderableListView(
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) {
        if (_currentFilter != TaskFilter.all) return; // 🔒 Disable reorder

        if (newIndex > oldIndex) newIndex--;

        setState(() {
          final task = pendingTasks.removeAt(oldIndex);
          pendingTasks.insert(newIndex, task);

          tasks
            ..clear()
            ..addAll(pendingTasks)
            ..addAll(completedTasks);
        });
      },
      children: [
        for (final task in pendingTasks) _buildTaskTile(task),

        if (completedTasks.isNotEmpty)
          Padding(
            key: const ValueKey('completed_header'),
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Text(
              'Completed',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),

        for (final task in completedTasks) _buildTaskTile(task),
      ],
    );
  }

  // 🧩 TASK TILE
  Widget _buildTaskTile(Task task, {bool isSubtask = false}) {
    final isHovered = _hoveredTasks[task] ?? false;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredTasks[task] = true),
      onExit: (_) => setState(() => _hoveredTasks[task] = false),

      child: Dismissible(
        key: ValueKey(task),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Colors.red.shade400,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) => deleteTask(task),

        child: ListTile(
          contentPadding: EdgeInsets.only(left: isSubtask ? 24 : 0),

          leading: Checkbox(
            value: task.isCompleted,
            shape: const CircleBorder(),
            onChanged: (_) => toggleTask(task),
          ),

          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.title,
                style: TextStyle(
                  decoration: task.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),

              if (task.dueDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        DateUtils.isSameDay(task.dueDate, DateTime.now())
                            ? 'Today'
                            : DateUtils.isSameDay(
                                task.dueDate,
                                DateTime.now().add(const Duration(days: 1)),
                              )
                            ? 'Tomorrow'
                            : '${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          // 🎯 HOVER ACTIONS
          trailing: task.isCompleted
              // 🗑 COMPLETED → DELETE ONLY (ON HOVER)
              ? AnimatedOpacity(
                  opacity: isHovered ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: InkResponse(
                    radius: 20,
                    onTap: () => deleteTask(task),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
                )
              // ⭐ + ⋮ PENDING TASK
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ⋮ MENU — ONLY ON HOVER
                    AnimatedOpacity(
                      opacity: isHovered ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),

                        // ✅ FIXED BACKGROUND COLOR
                        color: Theme.of(context).colorScheme.surface,

                        onSelected: (value) async {
                          switch (value) {
                            case 'deadline':
                              final date = await showDatePicker(
                                context: context,
                                initialDate: task.dueDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );

                              if (date != null) {
                                setState(() {
                                  task.dueDate = date;
                                });

                                // 🔄 Cancel old & reschedule
                                _cancelTaskNotification(task);
                                _scheduleTaskNotification(task);
                              }
                              break;

                            case 'subtask':
                              if (task.parentId == null) {
                                setState(() {
                                  _editingListId = task.listId;
                                  _editingParentTask = task;

                                  // ✅ INSERT SUBTASK RIGHT AFTER PARENT
                                  final parentIndex = tasks.indexOf(task);
                                  _editingInsertIndex = parentIndex + 1;

                                  _resetInlineEditor();
                                });
                              }
                              break;

                            case 'delete':
                              deleteTask(task);
                              break;

                            case 'new_list':
                              _showCreateListDialog(context);
                              break;

                            default:
                              _moveTaskToList(task, value);
                          }
                        },

                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'deadline',
                            child: Text(
                              'Add deadline',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),

                          if (task.parentId == null)
                            PopupMenuItem(
                              value: 'subtask',
                              child: Text(
                                'Add subtask',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ),
                            ),

                          PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              'Delete',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),

                          const PopupMenuDivider(),

                          ...lists.map(
                            (list) => PopupMenuItem(
                              value: list.id,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.list,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    list.name,
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const PopupMenuDivider(),

                          PopupMenuItem(
                            value: 'new_list',
                            child: Text(
                              'New list…',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ⭐ STAR — ON HOVER OR IF STARRED OR STARRED VIEW
                    AnimatedOpacity(
                      opacity:
                          (task.isStarred ||
                              isHovered ||
                              _currentFilter == TaskFilter.starred)
                          ? 1
                          : 0,
                      duration: const Duration(milliseconds: 150),
                      child: InkResponse(
                        radius: 20,
                        onTap: () => toggleStar(task),
                        child: Icon(
                          task.isStarred ? Icons.star : Icons.star_border,
                          color: task.isStarred ? Colors.amber : Colors.grey,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  int _taskCountForList(TaskList list) {
    return tasks.where((t) {
      // must belong to list
      if (t.listId != list.id) return false;

      // respect list visibility
      if (!list.isVisible) return false;

      return true;
    }).length;
  }

  // ☰ DRAWER
  Widget _buildDrawer(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          const SizedBox(height: 8),

          // ➕ CREATE TASK BUTTON
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () {
              _showAddTaskSheet(context);
            },
          ),

          const SizedBox(height: 16),

          // 🔵 ALL TASKS
          _drawerItem(
            icon: Icons.check_circle_outline,
            label: 'All tasks',
            selected: _isAllTasksView && _currentFilter == TaskFilter.all,
            onTap: () {
              setState(() {
                _isAllTasksView = true;
                _currentFilter = TaskFilter.all;
              });
            },
          ),

          // ⭐ STARRED
          _drawerItem(
            icon: Icons.star_border,
            label: 'Starred',
            selected: _currentFilter == TaskFilter.starred,
            onTap: () {
              setState(() {
                _currentFilter = TaskFilter.starred;
              });
            },
          ),

          const SizedBox(height: 16),

          // 📋 LISTS HEADER (expand / collapse)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                _listsExpanded = !_listsExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Lists',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  Icon(
                    _listsExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey,
                  ),
                ],
              ),
            ),
          ),

          // ⬇️ EXPANDABLE LISTS
          if (_listsExpanded)
            ...lists.map((list) {
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _selectedListId = list.id;
                    _isAllTasksView = false;
                    _currentFilter = TaskFilter.all;
                  });
                },
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: list.isVisible,
                  title: Row(
                    children: [
                      Expanded(child: Text(list.name)),
                      Text(
                        _taskCountForList(list).toString(),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.outline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  onChanged: (value) {
                    setState(() {
                      list.isVisible = value ?? true;
                    });
                  },
                ),
              );
            }),

          const SizedBox(height: 8),

          // ➕ CREATE NEW LIST
          _drawerItem(
            icon: Icons.add,
            label: 'Create new list',
            onTap: () {
              _showCreateListDialog(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    Widget? trailing,
    bool selected = false,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: selected
          ? BoxDecoration(
              color: Colors.blue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(24),
            )
          : null,
      child: ListTile(
        leading: Icon(icon, color: selected ? Colors.blue : null),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? Colors.blue : null,
          ),
        ),
        trailing: trailing,
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  Future<RepeatConfig?> showCustomRepeatDialog(BuildContext context) async {
    int interval = 1;
    String unit = 'day';
    TimeOfDay time = const TimeOfDay(hour: 23, minute: 30);
    DateTime startDate = DateTime.now();
    String ends = 'never';
    DateTime? endDate;
    int? occurrences;

    return showDialog<RepeatConfig>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Repeats every'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ───────── REPEATS EVERY ─────────
                  const Text('Repeats every'),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          controller: TextEditingController(
                            text: interval.toString(),
                          ),
                          onChanged: (v) => interval = int.tryParse(v) ?? 1,
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: unit,
                        items: const [
                          DropdownMenuItem(value: 'day', child: Text('day')),
                          DropdownMenuItem(value: 'week', child: Text('week')),
                          DropdownMenuItem(
                            value: 'month',
                            child: Text('month'),
                          ),
                          DropdownMenuItem(value: 'year', child: Text('year')),
                        ],
                        onChanged: (v) => setState(() => unit = v!),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 🕒 TIME
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(time.format(context)),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: time,
                      );
                      if (picked != null) {
                        setState(() => time = picked);
                      }
                    },
                  ),

                  const Divider(),

                  // ───────── STARTS ─────────
                  const Text('Starts'),
                  const SizedBox(height: 6),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${startDate.month}/${startDate.day}/${startDate.year}',
                    ),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: startDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() => startDate = date);
                      }
                    },
                  ),

                  const Divider(),

                  // ───────── ENDS ─────────
                  const Text('Ends'),

                  RadioListTile(
                    title: const Text('Never'),
                    value: 'never',
                    groupValue: ends,
                    onChanged: (v) => setState(() => ends = v!),
                  ),

                  RadioListTile(
                    title: Row(
                      children: [
                        const Text('On'),
                        const SizedBox(width: 8),
                        Text(
                          endDate == null
                              ? 'Select date'
                              : '${endDate!.month}/${endDate!.day}/${endDate!.year}',
                          style: TextStyle(
                            color: ends == 'on'
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    value: 'on',
                    groupValue: ends,
                    onChanged: (v) async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(() {
                          ends = 'on';
                          endDate = date;
                        });
                      }
                    },
                  ),

                  RadioListTile(
                    title: Row(
                      children: [
                        const Text('After'),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 60,
                          child: TextField(
                            enabled: ends == 'after',
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: '30',
                              isDense: true,
                            ),
                            onChanged: (v) =>
                                occurrences = int.tryParse(v) ?? 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text('occurrences'),
                      ],
                    ),
                    value: 'after',
                    groupValue: ends,
                    onChanged: (v) => setState(() {
                      ends = 'after';
                      occurrences ??= 30;
                    }),
                  ),
                ],
              ),

              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      RepeatConfig(
                        interval: interval,
                        unit: unit,
                        time: time,
                        startDate: startDate,
                        ends: ends,
                        endDate: endDate,
                        occurrences: occurrences,
                      ),
                    );
                  },
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ➕ ADD TASK
  void _showAddTaskSheet(BuildContext context) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    String repeatOption = 'Does not repeat';

    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();
    bool allDay = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // IMPORTANT
      builder: (context) {
        return SafeArea(
          child: Align(
            alignment: Alignment.center,
            // 🔥 CENTER
            child: FractionallySizedBox(
              widthFactor: 0.95, // responsive width
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: StatefulBuilder(
                    builder: (context, setModalState) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ❌ CLOSE
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),

                          // 📝 TITLE
                          TextField(
                            controller: titleController,
                            autofocus: true,
                            style: const TextStyle(fontSize: 18),
                            decoration: const InputDecoration(
                              hintText: 'Add title',
                              border: InputBorder.none,
                            ),
                            onChanged: (_) => setModalState(() {}),
                          ),

                          const Divider(),

                          // 📅 DATE & TIME
                          Row(
                            children: [
                              const Icon(Icons.schedule, size: 20),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: selectedDate,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (date != null) {
                                    setModalState(() => selectedDate = date);
                                  }
                                },
                                child: Text(
                                  '${selectedDate.month}/${selectedDate.day}/${selectedDate.year}',
                                ),
                              ),
                              if (!allDay)
                                TextButton(
                                  onPressed: () async {
                                    final time = await showTimePicker(
                                      context: context,
                                      initialTime: selectedTime,
                                    );
                                    if (time != null) {
                                      setModalState(() => selectedTime = time);
                                    }
                                  },
                                  child: Text(selectedTime.format(context)),
                                ),
                            ],
                          ),

                          // ☑️ ALL DAY
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('All day'),
                            value: allDay,
                            onChanged: (v) =>
                                setModalState(() => allDay = v ?? false),
                          ),

                          // 🔁 REPEAT
                          ListTile(
                            leading: const Icon(Icons.repeat),
                            title: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: repeatOption,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'Does not repeat',
                                    child: Text('Does not repeat'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Daily',
                                    child: Text('Daily'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Weekly on Thursday',
                                    child: Text('Weekly on Thursday'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Monthly on day 8',
                                    child: Text('Monthly on day 8'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Annually on Jan 8',
                                    child: Text('Annually on Jan 8'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Custom',
                                    child: Text('Custom'),
                                  ),
                                ],
                                onChanged: (v) async {
                                  if (v == 'Custom') {
                                    final result = await showCustomRepeatDialog(
                                      context,
                                    );
                                    if (result != null) {
                                      _customRepeat = result;
                                      setModalState(
                                        () => repeatOption = 'Custom',
                                      );
                                    }
                                  } else {
                                    _customRepeat = null;
                                    setModalState(() => repeatOption = v!);
                                  }
                                },
                              ),
                            ),
                          ),

                          // 🧾 DESCRIPTION
                          TextField(
                            controller: descriptionController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: 'Add description',
                              border: InputBorder.none,
                            ),
                          ),

                          const SizedBox(height: 8),

                          // 📋 LIST SELECTOR
                          DropdownButtonFormField<String>(
                            value: _selectedListId,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.list),
                              border: InputBorder.none,
                            ),
                            items: lists.map((list) {
                              return DropdownMenuItem(
                                value: list.id,
                                child: Text(list.name),
                              );
                            }).toList(),
                            onChanged: (v) {
                              setModalState(() => _selectedListId = v!);
                            },
                          ),

                          const SizedBox(height: 16),

                          // 💾 SAVE
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton(
                              onPressed: titleController.text.trim().isEmpty
                                  ? null
                                  : () {
                                      setState(() {
                                        tasks.add(
                                          Task(
                                            title: titleController.text.trim(),
                                            listId: _selectedListId,
                                            isStarred:
                                                _currentFilter ==
                                                TaskFilter.starred,
                                            starredAt:
                                                _currentFilter ==
                                                    TaskFilter.starred
                                                ? DateTime.now()
                                                : null,
                                          ),
                                        );
                                      });
                                      Navigator.pop(context);
                                    },
                              child: const Text('Save'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _saveNewTask(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return;
    addTask(text);
    Navigator.pop(context);
  }

  // 📋 CREATE LIST (UI ONLY)
  void _showCreateListDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create new list'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'List name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;

              setState(() {
                final id = DateTime.now().millisecondsSinceEpoch.toString();
                lists.add(
                  TaskList(
                    id: id,
                    name: name,
                    isVisible: true, // ✅ SHOW CARD IMMEDIATELY
                  ),
                );

                _selectedListId = id;
              });

              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRenameListDialog(TaskList list) {
    final controller = TextEditingController(text: list.name);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename list'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                list.name = controller.text.trim();
              });
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _handleListMenuAction(String value, TaskList list) {
    switch (value) {
      case 'rename':
        _showRenameListDialog(list); // ✅ FIX
        return; // 🚨 IMPORTANT: stop here

      case 'sort_my_order':
        setState(() {
          _listSortType[list.id] = ListSortType.myOrder;
        });
        break;

      case 'sort_date':
        setState(() {
          _listSortType[list.id] = ListSortType.date;
        });
        break;

      case 'sort_deadline':
        setState(() {
          _listSortType[list.id] = ListSortType.deadline;
        });
        break;

      case 'sort_starred':
        setState(() {
          _listSortType[list.id] = ListSortType.starred;
        });
        break;

      case 'sort_title':
        setState(() {
          _listSortType[list.id] = ListSortType.title;
        });
        break;

      case 'delete_completed':
        setState(() {
          tasks.removeWhere((t) => t.listId == list.id && t.isCompleted);
        });
        break;

      case 'delete':
        if (list.id == 'default') return;

        setState(() {
          tasks.removeWhere((t) => t.listId == list.id);
          lists.removeWhere((l) => l.id == list.id);
          _listSortType.remove(list.id);

          if (_selectedListId == list.id) {
            _isAllTasksView = true;
            _currentFilter = TaskFilter.all;
            _selectedListId = 'default';
          }
        });
        break;
    }
  }

  List<Task> _sortTasks(List<Task> tasks, String listId) {
    final sortType = _listSortType[listId] ?? ListSortType.myOrder;

    final sorted = List<Task>.from(tasks);

    switch (sortType) {
      case ListSortType.myOrder:
        // Do nothing (manual order)
        break;

      case ListSortType.date:
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;

      case ListSortType.deadline:
        sorted.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        break;

      case ListSortType.starred:
        sorted.sort((a, b) {
          if (a.starredAt == null && b.starredAt == null) return 0;
          if (a.starredAt == null) return 1;
          if (b.starredAt == null) return -1;
          return b.starredAt!.compareTo(a.starredAt!);
        });
        break;

      case ListSortType.title:
        sorted.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
    }

    return sorted;
  }

  @override
  void dispose() {
    _inlineFocusNode.dispose(); // ✅
    _inlineTitleCtrl.dispose();
    _inlineDetailsCtrl.dispose();
    super.dispose();
  }
}
