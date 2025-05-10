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
  Map<String, bool> _reviewedOrders = {};

  @override
  void initState() {
    super.initState();
    _loadOrderHistory();
    _loadReviewedOrders();
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

  Future<void> _loadReviewedOrders() async {
    try {
      // Получаем текущего пользователя
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      print('Загрузка информации о заказах с отзывами...');
      
      // Получаем все отзывы текущего пользователя
      final reviewsSnapshot = await FirebaseFirestore.instance
          .collection('reviews')
          .where('clientId', isEqualTo: user.uid)
          .where('type', isEqualTo: 'client_to_engineer')
          .get();
          
      // Создаем Map для быстрого поиска
      final Map<String, bool> reviewedMap = {};
      
      for (var doc in reviewsSnapshot.docs) {
        final data = doc.data();
        final String orderId = data['orderId'] ?? '';
        if (orderId.isNotEmpty) {
          reviewedMap[orderId] = true;
        }
      }
      
      print('Загружено ${reviewedMap.length} заказов с отзывами');
      
      if (mounted) {
        setState(() {
          _reviewedOrders = reviewedMap;
        });
      }
    } catch (e) {
      print('Ошибка при загрузке информации о заказах с отзывами: $e');
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
    // Получаем ID и имя инженера
    String engineerId = order['assignedTo'] ?? '';
    String engineerName = order['assignedToName'] ?? 'Неизвестный инженер';
    // ID заказа
    String orderId = order['id'] ?? '';
    // Проверяем, был ли оставлен отзыв
    bool hasReview = _reviewedOrders[orderId] ?? false;
    
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
                _buildDetailRow('Инженер', engineerName),
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

                // Добавляем кнопку для оценки инженера, если отзыв еще не оставлен
                if (!hasReview && engineerId.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF3D3D3D)),
                  const SizedBox(height: 16),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showRatingDialog(order),
                      icon: const Icon(Icons.star, color: Colors.amber),
                      label: const Text('Оценить инженера'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD04E4E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
                
                // Показываем информацию о том, что отзыв оставлен
                if (hasReview) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF3D3D3D)),
                  const SizedBox(height: 8),
                  
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.amber.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.amber,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Вы уже оставили отзыв об этом инженере',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
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

  // Метод для показа диалога оценки инженера
  void _showRatingDialog(Map<String, dynamic> order) {
    // Получаем ID и имя инженера
    String engineerId = order['assignedTo'] ?? '';
    String engineerName = order['assignedToName'] ?? 'Неизвестный инженер';
    String orderId = order['id'] ?? '';
    String historyId = order['originalOrderId'] ?? orderId;
    
    // Если нет ID инженера, не показываем диалог
    if (engineerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка: не найден ID инженера'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Значения для отзыва
    double rating = 5.0;
    String comment = '';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF2D2D2D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Оценить инженера',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Как вы оцениваете работу инженера $engineerName?',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${rating.toInt()}', 
                      style: const TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.star, color: Colors.amber, size: 30),
                  ],
                ),
                Slider(
                  value: rating,
                  min: 1.0,
                  max: 5.0,
                  divisions: 4,
                  label: rating.toInt().toString(),
                  activeColor: const Color(0xFFD04E4E),
                  inactiveColor: Colors.grey,
                  onChanged: (value) {
                    setState(() {
                      rating = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Оставьте комментарий (опционально)',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3D3D3D)),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3D3D3D)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFD04E4E)),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  onChanged: (value) {
                    comment = value;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Отмена',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _saveEngineerReview(
                  orderId, 
                  historyId,
                  engineerId, 
                  engineerName, 
                  rating.toInt(), 
                  comment
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD04E4E),
              ),
              child: const Text(
                'Отправить', 
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Метод для сохранения отзыва о инженере
  Future<void> _saveEngineerReview(
    String orderId,
    String historyId,
    String engineerId,
    String engineerName,
    int rating,
    String comment
  ) async {
    try {
      // Показываем индикатор загрузки
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сохранение отзыва...'),
          duration: Duration(seconds: 1),
        ),
      );
      
      // Получаем текущего пользователя
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Пользователь не авторизован');
      
      // Получаем данные пользователя
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      String userName = '';
      if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null) {
          userName = userData['name'] ?? '';
        }
      }
      
      // Создаем отзыв в коллекции reviews
      final reviewData = {
        'orderId': orderId,
        'historyId': historyId,
        'engineerId': engineerId,
        'engineerName': engineerName,
        'clientId': user.uid,
        'clientName': userName,
        'rating': rating,
        'comment': comment,
        'type': 'client_to_engineer', // Тип отзыва: от клиента инженеру
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      // Сохраняем отзыв
      await FirebaseFirestore.instance.collection('reviews').add(reviewData);
      
      // Обновляем средний рейтинг инженера
      await _updateEngineerAverageRating(engineerId);
      
      // Обновляем состояние, чтобы показать, что отзыв оставлен
      if (mounted) {
        setState(() {
          _reviewedOrders[orderId] = true;
        });
      }
      
      // Показываем сообщение об успехе
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Спасибо за ваш отзыв!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Ошибка при сохранении отзыва: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // Метод для обновления среднего рейтинга инженера
  Future<void> _updateEngineerAverageRating(String engineerId) async {
    try {
      if (engineerId.isEmpty) {
        print('Ошибка: ID инженера пустой, невозможно обновить рейтинг');
        return;
      }
      
      // Получаем все отзывы для данного инженера
      final reviewsSnapshot = await FirebaseFirestore.instance
          .collection('reviews')
          .where('engineerId', isEqualTo: engineerId)
          .where('type', isEqualTo: 'client_to_engineer')
          .get();
      
      if (reviewsSnapshot.docs.isEmpty) {
        print('Нет отзывов для инженера $engineerId');
        return;
      }
      
      // Вычисляем средний рейтинг
      double totalRating = 0;
      int count = 0;
      
      for (final doc in reviewsSnapshot.docs) {
        final data = doc.data();
        final rating = data['rating'] as int?;
        if (rating != null) {
          totalRating += rating;
          count++;
        }
      }
      
      if (count > 0) {
        final averageRating = totalRating / count;
        
        // Обновляем средний рейтинг инженера в его документе
        await FirebaseFirestore.instance
            .collection('users')
            .doc(engineerId)
            .update({
              'rating': averageRating,
              'ratingCount': count,
            });
        
        print('Средний рейтинг инженера обновлен: $averageRating ($count отзывов)');
      }
    } catch (e) {
      print('Ошибка при обновлении среднего рейтинга инженера: $e');
    }
  }
} 