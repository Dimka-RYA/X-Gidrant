import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../auth/auth_service.dart';
import '../models/task.dart';

class EngineerTasksScreen extends StatefulWidget {
  const EngineerTasksScreen({super.key});

  @override
  _EngineerTasksScreenState createState() => _EngineerTasksScreenState();
}

class _EngineerTasksScreenState extends State<EngineerTasksScreen> {
  StreamSubscription<QuerySnapshot>? _tasksSubscription;
  List<Task> _tasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _subscribeToTasks();
  }

  @override
  void dispose() {
    _tasksSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToTasks() {
    final user = AuthService().currentUser;
    if (user == null) return;

    // Отменяем существующую подписку перед созданием новой
    _tasksSubscription?.cancel();

    _tasksSubscription = FirebaseFirestore.instance
        .collection('orders')
        .where('assignedTo', isEqualTo: user.uid)
        .where('status', whereIn: ['назначен', 'прибыл', 'в работе'])
        .snapshots()
        .listen((snapshot) {
          // Проверяем, что виджет все еще в дереве
          if (!mounted) return;
          
          setState(() {
            _tasks = snapshot.docs.map((doc) => Task.fromFirestore(doc)).toList();
            _isLoading = false;
          });
        }, onError: (error) {
          print('Ошибка при получении заказов: $error');
          
          // Проверяем, что виджет все еще в дереве
          if (!mounted) return;
          
          setState(() {
            _isLoading = false;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFD04E4E),
        ),
      );
    }

    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'У вас пока нет активных заказов',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Здесь будут отображаться назначенные вам заказы',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tasks.length,
      itemBuilder: (context, index) {
        final task = _tasks[index];
        return _buildTaskCard(task);
      },
    );
  }

  Widget _buildTaskCard(Task task) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Заголовок карточки
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFD04E4E),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Заказ №${task.id}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    task.status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Основная информация
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('Услуга', task.title),
                const SizedBox(height: 8),
                _buildInfoRow('Адрес', task.address),
                const SizedBox(height: 8),
                _buildInfoRow('Клиент', task.userName),
                const SizedBox(height: 8),
                _buildInfoRow('Телефон', task.userPhone),
                if (task.additionalInfo.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildInfoRow('Доп. информация', task.additionalInfo),
                ],
                const SizedBox(height: 16),
                _buildInfoRow(
                  'Стоимость',
                  '${task.price.toStringAsFixed(2)} ${task.currency}',
                  valueColor: const Color(0xFFD04E4E),
                ),
              ],
            ),
          ),

          // Кнопки действий
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (task.status == 'назначен')
                  ElevatedButton(
                    onPressed: () => _arriveAtLocation(task),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD04E4E),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Прибыл на место',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (task.status == 'прибыл')
                  ElevatedButton(
                    onPressed: () => _completeWork(task),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD04E4E),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Завершить работу',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _arriveAtLocation(Task task) async {
    // Проверяем, что виджет все еще в дереве
    if (!mounted) return;
    
    // Показываем диалог для ввода кода подтверждения
    final confirmed = await _showConfirmationDialog(
      'Подтверждение прибытия',
      'Введите код подтверждения от клиента',
      task.arrivalCode,
    );

    if (confirmed) {
      try {
        await FirebaseFirestore.instance
            .collection('orders')
            .doc(task.id)
            .update({
          'status': 'прибыл',
          'statusUpdatedAt': FieldValue.serverTimestamp(),
          'statusHistory': FieldValue.arrayUnion([
            {
              'status': 'прибыл',
              'timestamp': FieldValue.serverTimestamp(),
              'note': 'Инженер прибыл на место',
            }
          ]),
        });
      } catch (e) {
        print('Ошибка при обновлении статуса заказа: $e');
        // Проверяем, что виджет все еще в дереве
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ошибка при обновлении статуса'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _completeWork(Task task) async {
    // Проверяем, что виджет все еще в дереве
    if (!mounted) return;
    
    // Показываем диалог для ввода кода завершения
    final confirmed = await _showConfirmationDialog(
      'Подтверждение завершения',
      'Введите код завершения работы от клиента',
      task.completionCode,
    );

    if (confirmed) {
      try {
        await FirebaseFirestore.instance
            .collection('orders')
            .doc(task.id)
            .update({
          'status': 'выполнен',
          'statusUpdatedAt': FieldValue.serverTimestamp(),
          'completedAt': FieldValue.serverTimestamp(),
          'statusHistory': FieldValue.arrayUnion([
            {
              'status': 'выполнен',
              'timestamp': FieldValue.serverTimestamp(),
              'note': 'Работа завершена',
            }
          ]),
        });

        // Перемещаем заказ в историю
        final orderDoc = await FirebaseFirestore.instance
            .collection('orders')
            .doc(task.id)
            .get();
        
        // Проверяем, что документ существует
        if (orderDoc.exists) {
          final orderData = orderDoc.data()!;
          
          // Получаем текущего пользователя для гарантии сохранения его идентификатора
          final user = AuthService().currentUser;
          final userId = user?.uid ?? '';
          final userName = user?.displayName ?? '';
          
          // Создаем запись в истории с явно указанными полями инженера
          await FirebaseFirestore.instance.collection('order_history').add({
            ...orderData,
            'completedAt': FieldValue.serverTimestamp(),
            'originalOrderId': task.id,
            'arrivalCode': orderData['arrivalCode'] ?? 'Не указан',
            'completionCode': orderData['completionCode'] ?? 'Не указан',
            // Гарантированно сохраняем информацию об инженере
            'assignedTo': userId.isNotEmpty ? userId : (orderData['assignedTo'] ?? ''),
            'assignedToName': userName.isNotEmpty ? userName : (orderData['assignedToName'] ?? ''),
          });
          
          // Выводим отладочную информацию
          print('Заказ ${task.id} перемещен в историю с assignedTo: $userId, assignedToName: $userName');
          
          // Удаляем заказ из основной коллекции
          await FirebaseFirestore.instance
              .collection('orders')
              .doc(task.id)
              .delete();
              
          // Показываем сообщение об успешном завершении
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Заказ успешно завершен и перемещен в историю'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        print('Ошибка при завершении задания: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при завершении задания: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<bool> _showConfirmationDialog(
    String title,
    String message,
    String correctCode,
  ) async {
    // Проверяем, что виджет все еще в дереве
    if (!mounted) return false;
    
    final codeController = TextEditingController();
    bool isLoading = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      hintText: 'Введите 4-значный код',
                      counterText: '',
                    ),
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () {
                    Navigator.of(context).pop(false);
                  },
                  child: const Text('Отмена'),
                ),
                ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    if (codeController.text.length != 4) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Введите 4-значный код'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    setState(() {
                      isLoading = true;
                    });

                    // Проверяем код
                    if (codeController.text == correctCode) {
                      Navigator.of(context).pop(true);
                    } else {
                      setState(() {
                        isLoading = false;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Неверный код'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD04E4E),
                  ),
                  child: const Text('Подтвердить'),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }
} 