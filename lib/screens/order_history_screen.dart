import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  _OrderHistoryScreenState createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _orderHistory = [];

  @override
  void initState() {
    super.initState();
    _loadOrderHistory();
  }

  Future<void> _loadOrderHistory() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Получаем текущего пользователя
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          _orderHistory = [];
        });
        return;
      }

      print('===== ЗАГРУЗКА ИСТОРИИ ЗАКАЗОВ КЛИЕНТА =====');
      print('Текущий пользователь: ID=${user.uid}, DisplayName=${user.displayName}');

      // Изменяем запрос для обхода необходимости составных индексов
      // Запрашиваем все недавние заказы и фильтруем на стороне клиента
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('order_history')
          .orderBy('completedAt', descending: true)
          .limit(100) // Ограничиваем количество для производительности
          .get();

      print('Получено документов истории: ${snapshot.docs.length}');

      // Вывод информации о первых нескольких документах для отладки
      print('Первые 5 документов истории (или меньше):');
      final previewDocs = snapshot.docs.take(5).toList();
      for (int i = 0; i < previewDocs.length; i++) {
        final doc = previewDocs[i];
        final data = doc.data() as Map<String, dynamic>;
        print('${i+1}. ID: ${doc.id}');
        print('   - userId: ${data['userId']}');
        print('   - userName: ${data['userName']}');
        print('   - assignedTo: ${data['assignedTo']}');
        print('   - Дата: ${data['completedAt'] != null ? (data['completedAt'] as Timestamp).toDate() : "не указана"}');
      }

      // Фильтруем результаты на стороне клиента
      final filteredDocs = snapshot.docs.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final String docUserId = data['userId']?.toString() ?? '';
        
        // Проверяем совпадение пользователя
        final bool matchesUserId = docUserId.trim() == user.uid.trim();
        
        if (matchesUserId) {
          print('Документ ${doc.id} соответствует текущему пользователю (userId: $docUserId)');
        }
        
        return matchesUserId;
      }).toList();

      print('Всего документов истории: ${snapshot.docs.length}, отфильтровано: ${filteredDocs.length}');

      // Преобразуем документы в объекты заказов
      final List<Map<String, dynamic>> orders = filteredDocs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();

      // Обновляем состояние
      setState(() {
        _orderHistory = orders;
        _isLoading = false;
      });
    } catch (e) {
      print('Ошибка при загрузке истории заказов: $e');
      setState(() {
        _isLoading = false;
        _orderHistory = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text(
          'Выполненные заказы',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF2D2D2D),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Добавляем кнопку для ручного обновления
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrderHistory,
            tooltip: 'Обновить историю',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFD04E4E),
              ),
            )
          : _orderHistory.isEmpty
              ? _buildEmptyHistory()
              : RefreshIndicator(
                  onRefresh: _loadOrderHistory,
                  color: const Color(0xFFD04E4E),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _orderHistory.length,
                    itemBuilder: (context, index) {
                      final order = _orderHistory[index];
                      return _buildOrderHistoryCard(order);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyHistory() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            'История выполненных заказов пуста',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Здесь будут отображаться заказы, которые вы выполнили',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderHistoryCard(Map<String, dynamic> order) {
    final bool isCompleted = order['status'] == 'выполнен';
    
    // Логи для отладки
    print('Данные заказа: ${order.toString()}');
    print('Код прибытия: ${order['arrivalCode']}');
    print('Код завершения: ${order['completionCode']}');
    
    // Получаем имя клиента
    String clientName = order['userName'] ?? order['clientName'] ?? 'Нет данных';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD04E4E).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Заголовок карточки
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Заказ №${order['id']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(order['completedAt']),
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD04E4E).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Color(0xFFD04E4E),
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Выполнен',
                        style: TextStyle(
                          color: Color(0xFFD04E4E),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
                _buildDetailRow('Услуга', order['title'] ?? 'Не указано'),
                _buildDetailRow('Клиент', clientName),
                _buildDetailRow('Адрес', order['address'] ?? 'Не указано'),
                _buildDetailRow('Стоимость', '${order['price'] ?? '0'} ${order['currency'] ?? '₽'}'),
                
                // Добавляем коды подтверждения
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF3D3D3D)),
                const SizedBox(height: 16),
                
                const Text(
                  'Коды подтверждения:',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                
                // Код подтверждения прибытия
                _buildConfirmationCode(
                  'Код прибытия',
                  order['arrivalCode'] ?? 'Не указан',
                  Icons.location_on,
                  Colors.green,
                ),
                
                const SizedBox(height: 8),
                
                // Код подтверждения завершения
                _buildConfirmationCode(
                  'Код завершения',
                  order['completionCode'] ?? 'Не указан',
                  Icons.check_circle_outline,
                  Colors.blue,
                ),
                
                // Если есть дополнительная информация
                if (order['additionalInfo'] != null && order['additionalInfo'].toString().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF3D3D3D)),
                  const SizedBox(height: 16),
                  
                  const Text(
                    'Дополнительная информация:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    order['additionalInfo'] ?? '',
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationCode(String label, String code, IconData icon, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF555555),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                code,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Дата не указана';
    
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else {
        return 'Некорректная дата';
      }
      
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    } catch (e) {
      return 'Ошибка даты';
    }
  }
} 