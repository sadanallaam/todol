import 'package:apsa/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:apsa/auth_service.dart';
import 'package:apsa/signin_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Simple Todo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        
        if (snapshot.hasData) {
          return const TodoPage();
        }
        
        return const SignInScreen();
      },
    );
  }
}

enum Priority { low, medium, high }

class Todo {
  String id;
  String title;
  String description;
  bool isCompleted;
  Priority priority;
  DateTime createdAt;
  DateTime? dueDate;
  String userId; // Added for user-specific todos

  Todo({
    String? id,
    required this.title,
    this.description = '',
    this.isCompleted = false,
    this.priority = Priority.medium,
    DateTime? createdAt,
    this.dueDate,
    required this.userId,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
       createdAt = createdAt ?? DateTime.now();

  Color get priorityColor {
    switch (priority) {
      case Priority.low: return Colors.green;
      case Priority.medium: return Colors.orange;
      case Priority.high: return Colors.red;
    }
  }

  bool get isOverdue {
    if (dueDate == null || isCompleted) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  // Convert to/from Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isCompleted': isCompleted,
      'priority': priority.index,
      'createdAt': Timestamp.fromDate(createdAt),
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'userId': userId,
    };
  }

  static Todo fromMap(Map<String, dynamic> map, String docId) {
    return Todo(
      id: docId, // Use document ID from Firestore
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      isCompleted: map['isCompleted'] ?? false,
      priority: Priority.values[map['priority'] ?? 1],
      createdAt: map['createdAt'] != null 
          ? (map['createdAt'] as Timestamp).toDate() 
          : DateTime.now(),
      dueDate: map['dueDate'] != null ? (map['dueDate'] as Timestamp).toDate() : null,
      userId: map['userId'] ?? '',
    );
  }
}

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final _searchController = TextEditingController();
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  String _searchQuery = '';
  bool _showCompleted = true;
  String? _userName;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final userData = await _authService.getUserData();
      if (userData != null && mounted) {
        setState(() {
          _userName = userData['name'];
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  // Updated stream to use subcollection structure: users/{userId}/todos
  Stream<List<Todo>> get _todosStream {
    final userId = _authService.currentUser?.uid;
    if (userId == null) return Stream.value([]);
    
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('todos')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Todo.fromMap(doc.data(), doc.id))
            .toList());
  }

  List<Todo> _filterTodos(List<Todo> todos) {
    return todos.where((todo) {
      final matchesSearch = todo.title.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCompleted = _showCompleted || !todo.isCompleted;
      return matchesSearch && matchesCompleted;
    }).toList();
  }

  // Updated to use subcollection structure
  Future<void> _addTodo(Todo todo) async {
    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) return;
      
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('todos')
          .doc(todo.id)
          .set(todo.toMap());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add todo: $e')),
        );
      }
    }
  }

  // Updated to use subcollection structure
  Future<void> _toggleTodo(String id, bool currentStatus) async {
    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) return;
      
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('todos')
          .doc(id)
          .update({
        'isCompleted': !currentStatus,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update todo: $e')),
        );
      }
    }
  }

  // Updated to use subcollection structure
  Future<void> _deleteTodo(String id) async {
    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) return;
      
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('todos')
          .doc(id)
          .delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete todo: $e')),
        );
      }
    }
  }

  // Updated to use subcollection structure
  Future<void> _editTodo(Todo updatedTodo) async {
    try {
      final userId = _authService.currentUser?.uid;
      if (userId == null) return;
      
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('todos')
          .doc(updatedTodo.id)
          .update(updatedTodo.toMap());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update todo: $e')),
        );
      }
    }
  }
  
//gagal login
  Future<void> _signOut() async {
    try {
      await _authService.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sign out: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Todo>>(
      stream: _todosStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final allTodos = snapshot.data ?? [];
        final filteredTodos = _filterTodos(allTodos);
        final completedCount = allTodos.where((todo) => todo.isCompleted).length;
        final overdueCount = allTodos.where((todo) => todo.isOverdue).length;

      //nama aplikasi
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _userName != null ? 'Hello, $_userName!' : 'My Tasks',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: _signOut,
              ),
            ],
          ),
          body: Column(
            children: [
              // Stats & Search
              Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.primary,
                child: Column(
                  children: [
                    
                    // Stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCard('Total', allTodos.length, Icons.list_alt, Colors.white70),
                        _buildStatCard('Done', completedCount, Icons.check_circle, Colors.green[300]!),
                        _buildStatCard('Overdue', overdueCount, Icons.warning, Colors.red[300]!),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Search
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (value) => setState(() => _searchQuery = value),
                            decoration: InputDecoration(
                              hintText: 'Search tasks...',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(25),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => setState(() => _showCompleted = !_showCompleted),
                          icon: Icon(
                            _showCompleted ? Icons.visibility : Icons.visibility_off,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Todo List
              Expanded(
                child: filteredTodos.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredTodos.length,
                        itemBuilder: (context, index) => _buildTodoCard(filteredTodos[index]),
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddEditDialog(),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String label, int value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 4),
        Text(value.toString(), 
             style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }

  Widget _buildTodoCard(Todo todo) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Checkbox(
          value: todo.isCompleted,
          onChanged: (_) => _toggleTodo(todo.id, todo.isCompleted),
        ),
        title: Text(
          todo.title,
          style: TextStyle(
            decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (todo.description.isNotEmpty)
              Text(todo.description, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: todo.priorityColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: todo.priorityColor),
                  ),
                  child: Text(
                    todo.priority.name.toUpperCase(),
                    style: TextStyle(fontSize: 10, color: todo.priorityColor, fontWeight: FontWeight.bold),
                  ),
                ),
                if (todo.dueDate != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    todo.isOverdue ? Icons.warning : Icons.schedule,
                    size: 12,
                    color: todo.isOverdue ? Colors.red : Colors.grey,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    _formatDate(todo.dueDate!),
                    style: TextStyle(
                      fontSize: 10,
                      color: todo.isOverdue ? Colors.red : Colors.grey,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _showAddEditDialog(todo: todo),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
              onPressed: () => _deleteTodo(todo.id),
            ),
          ],
        ),
        onTap: () => _showAddEditDialog(todo: todo),
      ),
    );
  }

//untuk task yang kgk ada samsek
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'No tasks found' : 'No tasks yet!',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty ? 'Try a different search' : 'Add your first task',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  void _showAddEditDialog({Todo? todo}) {
    final titleController = TextEditingController(text: todo?.title ?? '');
    final descController = TextEditingController(text: todo?.description ?? '');
    Priority priority = todo?.priority ?? Priority.medium;
    DateTime? dueDate = todo?.dueDate;

//add task dan edit task, serta isi isi nya
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(todo == null ? 'Add Task' : 'Edit Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title *', border: OutlineInputBorder()),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Priority>(
                value: priority,
                decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                items: Priority.values.map((p) => DropdownMenuItem(
                  value: p,
                  child: Text(p.name.toUpperCase()),
                )).toList(),
                onChanged: (value) => setDialogState(() => priority = value!),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: dueDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  setDialogState(() => dueDate = date);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Due Date', border: OutlineInputBorder()),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 16),
                      const SizedBox(width: 8),
                      Text(dueDate == null ? 'Select date' : _formatDate(dueDate!)),
                      const Spacer(),
                      if (dueDate != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setDialogState(() => dueDate = null),
                        ),
                    ],
                  ),
                ),
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
                if (titleController.text.trim().isEmpty) return;
                
                final userId = _authService.currentUser?.uid;
                if (userId == null) return;
                
                final newTodo = Todo(
                  id: todo?.id,
                  title: titleController.text.trim(),
                  description: descController.text.trim(),
                  priority: priority,
                  dueDate: dueDate,
                  isCompleted: todo?.isCompleted ?? false,
                  createdAt: todo?.createdAt,
                  userId: userId,
                );
                
                if (todo == null) {
                  _addTodo(newTodo);
                } else {
                  _editTodo(newTodo);
                }
                Navigator.pop(context);
              },
              child: Text(todo == null ? 'Add' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }

//tanggal tenggat
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(date.year, date.month, date.day);

    if (targetDate == today) return 'Today';
    if (targetDate == today.add(const Duration(days: 1))) return 'Tomorrow';
    if (targetDate.isBefore(today)) {
      final diff = today.difference(targetDate).inDays;
      return '$diff days ago';
    }
    return '${date.day}/${date.month}';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}