import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/auth_service.dart';
import 'dart:async';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with TickerProviderStateMixin {
  // Данные о заказах (в реальном приложении должны загружаться из API/БД)
  final List<OrderData> _orders = [
    OrderData(
      id: '777',
      service: 'Выгодно гидрант',
      address: 'Нижний овраг',
      status: OrderStatus.completed,
      date: '07.05.2024',
      time: '12:00 04.05.2024',
      cost: 312.50,
      currency: '₽',
    ),
    OrderData(
      id: '777',
      service: 'Выгодно гидрант',
      address: 'Нижний овраг',
      status: OrderStatus.rejected,
      date: '05.05.2024',
      time: '12:00 30.04.2024',
      cost: 312.50,
      currency: '₽',
    ),
    OrderData(
      id: '777',
      service: 'Выгодно гидрант',
      address: 'Нижний овраг',
      status: OrderStatus.completed,
      date: '30.04.2024',
      time: '12:00 26.04.2024',
      cost: 312.50,
      currency: '₽',
    ),
  ];

  // Список активных заказов из Firestore (не выполненные и не отмененные)
  List<OrderData> _activeOrders = [];
  
  // Список завершенных заказов (выполненные и отмененные)
  List<OrderData> _completedOrders = [];
  
  // Текущий заказ пользователя
  OrderData? _currentOrderData;
  
  // Идет ли загрузка заказов
  bool _isLoading = true;
  
  // Показывать ли меню с завершенными заказами
  bool _showCompletedOrdersMenu = false;
  
  // Выбранный фильтр статуса для завершенных заказов
  OrderStatus _selectedStatusFilter = OrderStatus.completed;
  
  // Подписка на обновления коллекции заказов
  StreamSubscription<QuerySnapshot>? _ordersSubscription;

  // Анимация для меню архива заказов
  AnimationController? _menuAnimationController;
  Animation<double>? _menuScaleAnimation;
  Animation<double>? _menuOpacityAnimation;
  
  // Анимация для переключения вкладок
  AnimationController? _tabAnimationController;
  Animation<double>? _tabIndicatorAnimation;
  
  // Анимация для пустого состояния (гидрант)
  AnimationController? _emptyStateAnimationController;
  Animation<double>? _emptyStateScaleAnimation;

  // Текущий активный заказ (может быть null, если нет активного заказа)
  OrderData? get _currentOrder {
    return _currentOrderData;
  }

  @override
  void initState() {
    super.initState();
    _loadOrders();
    
    // Инициализация анимации для меню
    _menuAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _menuScaleAnimation = CurvedAnimation(
      parent: _menuAnimationController!,
      curve: Curves.easeOutBack,
    );
    
    _menuOpacityAnimation = CurvedAnimation(
      parent: _menuAnimationController!,
      curve: Curves.easeIn,
    );
    
    // Инициализация анимации для вкладок
    _tabAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    
    _tabIndicatorAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _tabAnimationController!,
      curve: Curves.easeInOut,
    ));
    
    // Инициализация анимации для пустого состояния
    _emptyStateAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    
    _emptyStateScaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _emptyStateAnimationController!,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _menuAnimationController?.dispose();
    _tabAnimationController?.dispose();
    _emptyStateAnimationController?.dispose();
    super.dispose();
  }

  // Загрузка заказов пользователя из Firestore
  Future<void> _loadOrders() async {
    final user = AuthService().currentUser;
    
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    
    try {
      // Устанавливаем слушатель на коллекцию заказов для текущего пользователя
      _ordersSubscription = FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) {
            final activeOrders = <OrderData>[];
            final completedOrders = <OrderData>[];
            OrderData? currentOrder;
            
            for (var doc in snapshot.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final order = _convertToOrderData(doc.id, data);
              
              // Определяем тип заказа по статусу
              if (data['status'] == 'новый' || data['status'] == 'назначен' || data['status'] == 'в процессе' || data['status'] == 'на проверке') {
                // Если заказ "в обработке", добавляем его в активные
                activeOrders.add(order);
                
                // Если еще нет текущего заказа, устанавливаем его
                if (currentOrder == null) {
                  currentOrder = order;
                }
              } else if (data['status'] == 'выполнен' || data['status'] == 'отменен') {
                // Если заказ "выполнен" или "отменен", добавляем его в завершенные
                completedOrders.add(order);
                
                // Проверяем, изменился ли статус на "выполнен" и предлагаем оценить инженера
                _checkForCompletedOrder(doc.id, data);
              } else {
                // Если статус не определен или иной, добавляем в активные
                activeOrders.add(order);
              }
            }
            
            if (mounted) {
              setState(() {
                _activeOrders = activeOrders;
                _completedOrders = completedOrders;
                _currentOrderData = currentOrder;
                _isLoading = false;
              });
            }
          }, onError: (error) {
            print('Ошибка при загрузке заказов: $error');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          });
    } catch (e) {
      print('Ошибка при настройке слушателя заказов: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Метод для обновления заказов (pull-to-refresh)
  Future<void> _refreshOrders() async {
    // Отменяем текущую подписку, если она есть
    _ordersSubscription?.cancel();
    _ordersSubscription = null;
    
    setState(() {
      _isLoading = true;
      _activeOrders = [];
      _completedOrders = [];
      _currentOrderData = null;
    });
    
    // Загружаем заказы заново
    await _loadOrders();
  }
  
  // Конвертация данных из Firestore в OrderData
  OrderData _convertToOrderData(String docId, Map<String, dynamic> data) {
    // Определяем статус заказа
    OrderStatus status;
    switch (data['status']) {
      case 'новый':
      case 'назначен':
      case 'в процессе':
      case 'на проверке':
        status = OrderStatus.active;
        break;
      case 'выполнен':
        status = OrderStatus.completed;
        break;
      case 'отменен':
        status = OrderStatus.rejected;
        break;
      default:
        status = OrderStatus.active;
    }
    
    // Форматируем дату
    String formattedDate = '';
    String formattedTime = '';
    
    if (data['createdAt'] != null) {
      try {
        final timestamp = data['createdAt'] as Timestamp;
        final date = timestamp.toDate();
        
        // Форматируем дату: DD.MM.YYYY
        formattedDate = '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
        
        // Форматируем время: HH:MM DD.MM.YYYY
        formattedTime = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} $formattedDate';
      } catch (e) {
        print('Ошибка при форматировании даты: $e');
        formattedDate = 'Нет данных';
        formattedTime = 'Нет данных';
      }
    }
    
    // Создаем список событий статуса (если есть)
    final List<OrderStatusEvent> statusEvents = [];
    if (data['statusEvents'] != null && data['statusEvents'] is List) {
      for (var event in data['statusEvents']) {
        if (event is Map<String, dynamic>) {
          statusEvents.add(OrderStatusEvent(
            status: event['status'] ?? 'Статус',
            dateTime: event['dateTime'] ?? 'Нет времени',
            notes: event['notes'],
            color: _getStatusColor(event['status']),
          ));
        }
      }
    }
    
    // Подготавливаем данные о кодах подтверждения
    Map<String, dynamic> additionalData = {};
    
    // Сохраняем оригинальную дополнительную информацию, если она есть
    if (data['additionalInfo'] != null) {
      if (data['additionalInfo'] is String) {
        additionalData['info'] = data['additionalInfo'];
      } else if (data['additionalInfo'] is Map) {
        // Если additionalInfo уже карта, добавляем её содержимое
        additionalData.addAll(data['additionalInfo'] as Map<String, dynamic>);
      }
    }
    
    // Добавляем коды подтверждения
    additionalData['arrivalCode'] = data['arrivalCode'] ?? 'Не указан';
    additionalData['completionCode'] = data['completionCode'] ?? 'Не указан';
    
    // Отладочная информация
    print('ID: $docId, Добавлены коды: прибытие=${additionalData['arrivalCode']}, завершение=${additionalData['completionCode']}');
    
    // Создаем и возвращаем объект OrderData
    return OrderData(
      id: docId,
      service: data['title'] ?? 'Без названия',
      address: data['address'] ?? 'Без адреса',
      status: status,
      date: formattedDate,
      time: formattedTime,
      cost: (data['price'] is num) ? (data['price'] as num).toDouble() : 0.0,
      currency: data['currency'] ?? '₽',
      additionalInfo: additionalData,
      statusEvents: statusEvents,
      originalStatus: data['status'],
    );
  }
  
  // Получение цвета статуса
  Color _getStatusColor(String? status) {
    switch (status) {
      case 'новый':
        return Colors.blue;
      case 'назначен':
        return Colors.orange.shade700;
      case 'в процессе':
        return Colors.orange;
      case 'на проверке':
        return Colors.orange.shade300;
      case 'выполнен':
        return Colors.green;
      case 'отменен':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Получение читаемого текста статуса
  String _getStatusText(String? status) {
    switch (status) {
      case 'новый':
        return 'Новый';
      case 'назначен':
        return 'Назначен мастер';
      case 'в процессе':
        return 'В процессе';
      case 'на проверке':
        return 'На проверке';
      case 'выполнен':
        return 'Выполнен';
      case 'отменен':
        return 'Отменен';
      default:
        return status ?? 'Неизвестный статус';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Кнопка для открытия меню с выполненными и отмененными заказами
          IconButton(
            icon: Icon(
              _showCompletedOrdersMenu 
                  ? Icons.close 
                  : Icons.filter_list,
              color: const Color(0xFFD04E4E),
            ),
            onPressed: () {
              setState(() {
                _showCompletedOrdersMenu = !_showCompletedOrdersMenu;
                
                if (_showCompletedOrdersMenu) {
                  // Запускаем анимацию появления меню
                  _menuAnimationController!.forward();
                  
                  // Сбрасываем и запускаем анимацию пустого состояния, если нет заказов
                  _emptyStateAnimationController!.reset();
                  _emptyStateAnimationController!.forward();
                } else {
                  // Запускаем анимацию исчезновения меню
                  _menuAnimationController!.reverse();
                }
              });
            },
            tooltip: 'Архив заказов',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading 
          ? _buildLoadingView()
          : RefreshIndicator(
              onRefresh: _refreshOrders,
              color: const Color(0xFFD04E4E),
              child: Stack(
                children: [
                  // Основное содержимое истории
                  SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: MediaQuery.of(context).size.height - 
                                   AppBar().preferredSize.height - 
                                   MediaQuery.of(context).padding.top - 
                                   MediaQuery.of(context).padding.bottom,
                      ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                          // Заголовок "Активные заказы"
              const Padding(
                            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                              'Активные заказы',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
                          // Список активных заказов
                          _activeOrders.isEmpty
                            ? _buildEmptyHistoryView(message: 'У вас пока нет активных заказов')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                                itemCount: _activeOrders.length,
                      itemBuilder: (context, index) {
                                  return _buildOrderHistoryCard(_activeOrders[index]);
                      },
                    ),
            ],
          ),
        ),
                  ),
                  
                  // Контекстное меню с завершенными заказами (снизу вверх) с анимацией
                  if (_showCompletedOrdersMenu)
                    AnimatedBuilder(
                      animation: _menuAnimationController!,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _menuOpacityAnimation!.value,
                          child: Transform.scale(
                            scale: _menuScaleAnimation!.value,
                            alignment: Alignment.bottomCenter,
                            child: child,
                          ),
                        );
                      },
                      child: _buildCompletedOrdersMenu(),
                    ),
                ],
              ),
            ),
      ),
    );
  }
  
  // Виджет отображения индикатора загрузки
  Widget _buildLoadingView() {
    return const Center(
      child: CircularProgressIndicator(
        color: Color(0xFFD04E4E),
      ),
    );
  }

  // Виджет для отображения пустой истории заказов с GIF-анимацией
  Widget _buildEmptyHistoryView({String message = 'У вас пока нет истории заказов'}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // GIF-анимация грустного гидранта с анимацией
            AnimatedBuilder(
              animation: _emptyStateAnimationController ?? const AlwaysStoppedAnimation(1.0),
              builder: (context, child) {
                return Transform.scale(
                  scale: _emptyStateScaleAnimation?.value ?? 1.0,
                  child: child,
                );
              },
              child: SizedBox(
              width: 200,
              height: 200,
              child: Image.asset(
                'lib/assets/sad_red_gid.gif',
                fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Текст об отсутствии заказов с анимацией появления
            AnimatedOpacity(
              opacity: _emptyStateAnimationController?.value ?? 1.0,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeIn,
              child: Text(
                message,
                style: const TextStyle(
                color: Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Выдвижное меню для отображения завершенных заказов (снизу вверх)
  Widget _buildCompletedOrdersMenu() {
    // Получаем отфильтрованные заказы
    final filteredOrders = _completedOrders
        .where((order) => order.status == _selectedStatusFilter)
        .toList();
    
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: MediaQuery.of(context).size.height * 0.7,
      child: GestureDetector(
        onVerticalDragEnd: (details) {
          // Если скорость свайпа вниз больше порогового значения, закрываем меню
          if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
            setState(() {
              _showCompletedOrdersMenu = false;
            });
          }
        },
        child: DraggableScrollableSheet(
          initialChildSize: 1.0, // Начальный размер от максимальной высоты
          minChildSize: 0.3, // Минимальный размер (30% от высоты)
          maxChildSize: 1.0, // Максимальный размер (100% от высоты)
          expand: false,
          builder: (context, scrollController) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
          boxShadow: [
            BoxShadow(
                    color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
                    offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                  // Полоска для закрытия (делаем интерактивной)
                  GestureDetector(
                    onVerticalDragEnd: (details) {
                      // Если скорость свайпа вниз больше порогового значения, закрываем меню
                      if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
                        setState(() {
                          _showCompletedOrdersMenu = false;
                        });
                      }
                    },
                    onTap: () {
                      setState(() {
                        _showCompletedOrdersMenu = false;
                      });
                    },
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 8, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  
                  // Заголовок меню
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD04E4E).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.history,
                                color: Color(0xFFD04E4E),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 8),
                const Text(
                              'Архив заказов',
                  style: TextStyle(
                                fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () {
                            setState(() {
                              _showCompletedOrdersMenu = false;
                            });
                          },
                ),
              ],
            ),
                  ),
                  
                  // Вкладки "Выполнено" и "Отменено"
                  _buildStatusTabs(),
                  
                  // Список завершенных заказов
                  Expanded(
                    child: filteredOrders.isEmpty
                        ? _buildEmptyHistoryView(message: 'У вас пока нет заказов с таким статусом')
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.all(16),
                            itemCount: filteredOrders.length,
                            itemBuilder: (context, index) {
                              return _buildOrderHistoryCard(filteredOrders[index]);
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
  
  // Вкладки для фильтрации по статусам с анимированным переключением
  Widget _buildStatusTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
          Row(
            children: [
              _buildStatusTab(
                label: 'Выполнено',
                count: _completedOrders.where((order) => order.status == OrderStatus.completed).length,
                color: Colors.green,
                isSelected: _selectedStatusFilter == OrderStatus.completed,
                onTap: () {
                  setState(() {
                    if (_selectedStatusFilter != OrderStatus.completed) {
                      _selectedStatusFilter = OrderStatus.completed;
                      
                      // Сбрасываем анимацию и запускаем в обратном направлении
                      _tabAnimationController!.reset();
                      _tabAnimationController!.forward();
                      
                      // Запускаем анимацию пустого состояния
                      _emptyStateAnimationController!.reset();
                      _emptyStateAnimationController!.forward();
                    }
                  });
                },
              ),
              const SizedBox(width: 12),
              _buildStatusTab(
                label: 'Отменено',
                count: _completedOrders.where((order) => order.status == OrderStatus.rejected).length,
                color: Colors.red,
                isSelected: _selectedStatusFilter == OrderStatus.rejected,
                onTap: () {
                  setState(() {
                    if (_selectedStatusFilter != OrderStatus.rejected) {
                      _selectedStatusFilter = OrderStatus.rejected;
                      
                      // Сбрасываем анимацию и запускаем
                      _tabAnimationController!.reset();
                      _tabAnimationController!.forward();
                      
                      // Запускаем анимацию пустого состояния
                      _emptyStateAnimationController!.reset();
                      _emptyStateAnimationController!.forward();
                    }
                  });
                },
              ),
            ],
          ),
          // Индикатор выбранной вкладки с анимацией
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: _tabAnimationController!,
            builder: (context, child) {
              return Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            height: 3,
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ),
                          Positioned(
                            left: _selectedStatusFilter == OrderStatus.completed ? 16 : null,
                            right: _selectedStatusFilter == OrderStatus.rejected ? 16 : null,
                            child: Container(
                              width: (MediaQuery.of(context).size.width - 44 - 12) / 2 * _tabIndicatorAnimation!.value,
                              height: 3,
                              decoration: BoxDecoration(
                                color: _selectedStatusFilter == OrderStatus.completed 
                                    ? Colors.green.withOpacity(0.6) 
                                    : Colors.red.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                    ),
                  ),
                ],
              ),
                    ),
                  ],
                ),
              );
            },
            ),
          ],
        ),
      );
    }
  
  // Отдельная вкладка для фильтра по статусу
  Widget _buildStatusTab({
    required String label,
    required int count,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.1) : Colors.grey.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color.withOpacity(0.5) : Colors.grey.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : Colors.grey[700],
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? color.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? color : Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Карточка с информацией о заказе из истории
  Widget _buildOrderHistoryCard(OrderData order) {
    // Получаем статус из оригинальных данных заказа
    Color statusColor = _getStatusColor(order.originalStatus);
    String statusText = _getStatusText(order.originalStatus);
    
    // Получаем текст для дополнительной информации
    String additionalInfoText = '';
    if (order.additionalInfo != null) {
      if (order.additionalInfo is String) {
        additionalInfoText = order.additionalInfo as String;
      } else if (order.additionalInfo is Map) {
        // Если это Map, отображаем только поле info, если оно есть
        final Map<dynamic, dynamic> infoMap = order.additionalInfo as Map;
        if (infoMap.containsKey('info')) {
          additionalInfoText = infoMap['info'].toString();
        }
      }
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Открываем окно с подробной информацией о заказе
            _showOrderDetails(order);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                // Верхняя строка: ID заказа и дата
                Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Заказ #${order.id}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      order.date,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                
                // Название услуги
                Text(
                  order.service,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                
                // Адрес
                Row(
                        children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                            child: Text(
                        order.address,
                              style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Нижняя строка: Стоимость и статус
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                      '${order.cost.toStringAsFixed(2)} ${order.currency}',
                                  style: const TextStyle(
                        fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusText,
                                    style: TextStyle(
                                      fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                                    ),
                                  ),
                              ],
                            ),
                
                // Дополнительная информация (при наличии)
                if (additionalInfoText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                            Text(
                    'Доп. информация: $additionalInfoText',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Показать детальную информацию о заказе в модальном окне
  void _showOrderDetails(OrderData order) {
    // Определяем цвет статуса
    Color statusColor;
    String statusText;
    
    // Получаем статус из оригинальных данных заказа
    statusColor = _getStatusColor(order.originalStatus);
    statusText = _getStatusText(order.originalStatus);
    
    // Создаем переменную для отслеживания состояния развернутости дополнительной информации
    bool isDetailsExpanded = false;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
    return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
        color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                  // Полоска для закрытия
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 16),
                      width: 40,
                      height: 4,
                            decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  // Заголовок модального окна
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
            children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            order.status == OrderStatus.active ? Icons.access_time : 
                            order.status == OrderStatus.completed ? Icons.check_circle : 
                            Icons.cancel,
                            color: statusColor,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                                order.service,
                style: const TextStyle(
                                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
                                  Text(
                                'Заказ #${order.id}',
                                    style: TextStyle(
                                  fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Основная информация и детали заказа
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Информация о заказе (всегда отображается)
                          _buildOrderInfoSection(order, statusColor, statusText),
                          
                          const SizedBox(height: 20),
                          
                          // Раздел с дополнительной информацией (раскрывающийся)
              Container(
                decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Заголовок дополнительной информации с кнопкой раскрытия
                                GestureDetector(
                                  onTap: () {
                                    setModalState(() {
                                      isDetailsExpanded = !isDetailsExpanded;
                                    });
                                  },
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                            Text(
                                        'Детали заказа',
                  style: TextStyle(
                                          fontSize: 16,
                    fontWeight: FontWeight.bold,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                      AnimatedRotation(
                                        turns: isDetailsExpanded ? 0.5 : 0.0,
                                        duration: const Duration(milliseconds: 300),
                                        child: Icon(
                                          Icons.keyboard_arrow_down,
                                          color: isDetailsExpanded 
                                              ? const Color(0xFFD04E4E)
                                              : Colors.grey,
                ),
              ),
            ],
          ),
                                ),
                                
                                // Анимированное раскрытие/скрытие дополнительной информации
                                AnimatedCrossFade(
                                  firstChild: const SizedBox(height: 0),
                                  secondChild: Padding(
                                    padding: const EdgeInsets.only(top: 16),
              child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                                        if (order.additionalInfo != null && order.additionalInfo!.isNotEmpty)
                                          _buildDetailRow('Дополнительная информация:', order.additionalInfo!),
                                        
                                        if (order.statusEvents != null && order.statusEvents!.isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          const Text(
                                            'История статусов:',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                  const SizedBox(height: 8),
                                          ..._buildStatusEventsTimeline(order.statusEvents!),
                                        ],
                                      ],
                                    ),
                                  ),
                                  crossFadeState: isDetailsExpanded 
                                      ? CrossFadeState.showSecond 
                                      : CrossFadeState.showFirst,
                                  duration: const Duration(milliseconds: 300),
            ),
          ],
        ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Кнопка действия внизу (если заказ активный)
                  if (order.status == OrderStatus.active)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton(
                        onPressed: () {
                          // Действие для активного заказа (например, отмена)
                          Navigator.pop(context);
                          // Здесь можно добавить логику отмены заказа
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[600],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Отменить заказ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                              ),
                            ),
                        ],
                      ),
            );
          },
        );
      },
                    );
                  } 

  // Построение раздела с основной информацией о заказе
  Widget _buildOrderInfoSection(OrderData order, Color statusColor, String statusText) {
                    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            'Информация о заказе',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRow('Услуга:', order.service),
          _buildDetailRow('Дата:', order.time),
          _buildDetailRow('Адрес:', order.address),
          _buildDetailRow('Стоимость:', '${order.cost.toStringAsFixed(2)} ${order.currency}', 
            valueColor: const Color(0xFFD04E4E)),
          _buildDetailRow('Статус:', statusText, valueColor: statusColor),
          
          // Добавляем коды подтверждения
          if (order.additionalInfo is Map<String, dynamic> || order.additionalInfo is Map) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            
        Text(
              'Коды подтверждения',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            
            // Код прибытия
            _buildConfirmationCode('Код прибытия', 
              _getCodeFromData(order, 'arrivalCode'), Icons.location_on, Colors.green),
              
            const SizedBox(height: 8),
            
            // Код завершения
            _buildConfirmationCode('Код завершения', 
              _getCodeFromData(order, 'completionCode'), Icons.check_circle, Colors.blue),
          ],
        ],
      ),
    );
  }

  // Извлекаем код из данных заказа
  String _getCodeFromData(OrderData order, String codeType) {
    if (order.additionalInfo is Map<String, dynamic>) {
      return (order.additionalInfo as Map<String, dynamic>)[codeType] ?? 'Не указан';
    } else if (order.additionalInfo is String) {
      // Если есть additionalInfo в виде строки, пытаемся искать код в ней
      final String info = order.additionalInfo as String;
      if (info.contains(codeType)) {
        // Очень упрощенный парсинг, можно улучшить при необходимости
        final startIndex = info.indexOf(codeType) + codeType.length;
        final endIndex = info.indexOf('\n', startIndex);
        if (endIndex > startIndex) {
          return info.substring(startIndex, endIndex).trim();
        }
      }
    }
    return 'Не указан';
  }
  
  // Виджет для отображения кода подтверждения
  Widget _buildConfirmationCode(String label, String code, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
      children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
        Text(
                  code,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Построение строки с парой "название: значение"
  Widget _buildDetailRow(String label, dynamic value, {Color? valueColor}) {
    // Преобразуем значение в строку в зависимости от типа
    String displayValue = '';
    
    if (value is String) {
      displayValue = value;
    } else if (value is Map) {
      // Если это карта, извлекаем поле info, если оно есть
      if (value.containsKey('info')) {
        displayValue = value['info'].toString();
      } else {
        // Иначе преобразуем всю карту в строку, исключая arrivalCode и completionCode
        final filteredMap = Map<dynamic, dynamic>.from(value)
          ..removeWhere((key, _) => key == 'arrivalCode' || key == 'completionCode');
        
        if (filteredMap.isNotEmpty) {
          displayValue = filteredMap.toString();
        } else {
          displayValue = 'Нет дополнительной информации';
        }
      }
    } else {
      // Для других типов просто преобразуем в строку
      displayValue = value?.toString() ?? '';
    }
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
          label,
          style: TextStyle(
                fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
          ),
        Expanded(
          child: Text(
              displayValue,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
          ),
        ),
      ],
      ),
    );
  }

  // Построение временной шкалы событий статуса заказа
  List<Widget> _buildStatusEventsTimeline(List<OrderStatusEvent> events) {
    final List<Widget> timelineItems = [];
    
    for (int i = 0; i < events.length; i++) {
      final event = events[i];
      final isLast = i == events.length - 1;
      
      timelineItems.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            // Точка и линия временной шкалы
            Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: event.color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 30,
                    color: Colors.grey[300],
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Информация о событии
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
        Text(
                    event.status,
          style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: event.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.dateTime,
                    style: TextStyle(
                      fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
                  if (event.notes != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[800],
                        fontStyle: FontStyle.italic,
          ),
        ),
      ],
                  if (!isLast)
                    const SizedBox(height: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }

    return timelineItems;
  }

  // Метод для проверки завершенных заказов и предложения оценить инженера
  Future<void> _checkForCompletedOrder(String orderId, Map<String, dynamic> data) async {
    try {
      // Проверяем, что заказ имеет статус "выполнен"
      if (data['status'] == 'выполнен') {
        // Проверяем, есть ли в заказе поле reviewRequested
        // Если поле отсутствует, считаем что его значение true (показать диалог)
        // Если поле есть и равно false, то не показываем диалог
        final bool showReviewDialog = data['reviewRequested'] ?? true;
        
        if (!showReviewDialog) {
          print('Для заказа $orderId уже показывали окно оценки (reviewRequested = false)');
          return;
        }
        
        // Задержка перед показом диалога, чтобы избежать конфликтов с другими обновлениями UI
        await Future.delayed(const Duration(seconds: 1));
        
        if (!mounted) return;
        
        // Получаем данные инженера для отзыва
        final String engineerId = data['assignedTo'] ?? '';
        final String engineerName = data['assignedToName'] ?? 'Инженер';
        
        if (engineerId.isNotEmpty) {
          // Показываем диалог с предложением оценить инженера
          _showEngineerRatingDialog(
            orderId: orderId,
            engineerId: engineerId, 
            engineerName: engineerName
          );
          
          // Устанавливаем флаг reviewRequested = false в заказе
          await _markReviewAsRequested(orderId);
        }
      }
    } catch (e) {
      print('Ошибка при проверке завершенных заказов: $e');
    }
  }
  
  // Метод для установки флага reviewRequested = false в заказе
  Future<void> _markReviewAsRequested(String orderId) async {
    try {
      // Обновляем заказ в коллекции orders
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .update({
            'reviewRequested': false,
          });
      
      print('Установлен флаг reviewRequested = false для заказа $orderId');
    } catch (e) {
      print('Ошибка при обновлении флага reviewRequested: $e');
    }
  }
  
  // Метод для показа диалога оценки инженера
  void _showEngineerRatingDialog({
    required String orderId,
    required String engineerId,
    required String engineerName,
  }) {
    // Если компонент уже размонтирован, не показываем диалог
    if (!mounted) return;
    
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
            'Оцените работу инженера',
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ваш заказ выполнен! Как вы оцениваете работу инженера $engineerName?',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${rating.toInt()}', 
                      style: const TextStyle(
                        fontSize: 32, 
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.star, color: Colors.amber, size: 38),
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
                // При нажатии "Позже" ничего не делаем, 
                // так как флаг reviewRequested уже установлен на false
              },
              child: const Text(
                'Позже',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _saveEngineerReview(
                  orderId, 
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
      final user = AuthService().currentUser;
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
      
      // Получаем историческую запись для данного заказа
      final historySnapshot = await FirebaseFirestore.instance
          .collection('order_history')
          .where('originalOrderId', isEqualTo: orderId)
          .get();
      
      String historyId = '';
      if (historySnapshot.docs.isNotEmpty) {
        historyId = historySnapshot.docs.first.id;
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

// Модель события статуса заказа
class OrderStatusEvent {
  final String status;
  final String dateTime;
  final String? notes;
  final Color color;

  OrderStatusEvent({
    required this.status,
    required this.dateTime,
    this.notes,
    required this.color,
  });
}

// Модель данных заказа
class OrderData {
  final String id;
  final String service;
  final String address;
  final OrderStatus status;
  final String date;
  final String time;
  final double cost;
  final String currency;
  final dynamic additionalInfo;
  final List<OrderStatusEvent>? statusEvents;
  final String? originalStatus;

  OrderData({
    required this.id,
    required this.service,
    required this.address,
    required this.status,
    required this.date,
    required this.time,
    required this.cost,
    required this.currency,
    this.additionalInfo,
    this.statusEvents,
    this.originalStatus,
  });
}

// Перечисление возможных статусов заказа
enum OrderStatus {
  active,
  completed,
  rejected,
} 
