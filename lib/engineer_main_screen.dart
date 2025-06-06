import 'package:flutter/material.dart';
import 'screens/profile_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'auth/auth_service.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:math';
// Syncfusion DateRangePicker
import 'package:syncfusion_flutter_datepicker/datepicker.dart' as dp;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../models/task.dart';
// Добавляем импорт Filter для составных запросов к Firestore
import 'package:cloud_firestore/cloud_firestore.dart' show Filter;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;

class EngineerMainScreen extends StatefulWidget {
  const EngineerMainScreen({super.key});

  @override
  _EngineerMainScreenState createState() => _EngineerMainScreenState();
}

class _EngineerMainScreenState extends State<EngineerMainScreen> {
  int _selectedIndex = 0; // Текущая вкладка
  // PageController для навигации между экранами
  final PageController _pageController = PageController(
    initialPage: 0,
    keepPage: true,
    viewportFraction: 1.0,
  );
  
  // Подписка на обновления коллекции заказов
  StreamSubscription<QuerySnapshot>? _ordersSubscription;
  
  // Таймер для проверки существования активного заказа
  Timer? _checkActiveOrderTimer;
  
  // Список экранов для инженера
  late List<Widget> _screens;
  
  // Ссылка на _EngineerTasksScreenState для доступа к активному заказу
  final GlobalKey<_EngineerTasksScreenState> _tasksScreenKey = GlobalKey<_EngineerTasksScreenState>();
  
  Task? _activeTask;
  StreamSubscription<DocumentSnapshot>? _taskSubscription;
  StreamSubscription<QuerySnapshot>? _assignedTasksSubscription;

  @override
  void initState() {
    super.initState();
    _screens = [
      EngineerIncomeScreen(tasksScreenKey: _tasksScreenKey),
    const EngineerTasksScreen(),
    const EngineerHistoryScreen(),
      const EngineerProfileScreen(),
  ];
    _subscribeToAssignedTasks();
  }

  @override
  void dispose() {
    // Отменяем все подписки при уничтожении виджета
    _taskSubscription?.cancel();
    _assignedTasksSubscription?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // Позволяет контенту расширяться под навигационную панель
      body: Stack(
        children: [
          // PageView для свайпа между экранами
          PageView(
            controller: _pageController,
            physics: const PageScrollPhysics(),
            pageSnapping: true,
            allowImplicitScrolling: true,
            onPageChanged: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            children: _screens,
          ),
          
          // Навигационная панель внизу
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(0, Icons.attach_money, 'Доход'),
                  _buildNavItem(1, Icons.local_fire_department, 'Заявки'),
                  _buildNavItem(2, Icons.history, 'История'),
                  _buildNavItem(3, Icons.person_outline, 'Профиль'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    final accentColor = const Color(0xFFD04E4E);
    final defaultColor = Colors.white;
    
    return InkWell(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuad,
        );
      },
      child: Container(
        width: 80,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Иконка и текст
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: isSelected ? accentColor : defaultColor,
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    color: isSelected 
                      ? accentColor 
                      : defaultColor,
                    fontSize: 10,
                  ),
                  child: Text(label),
                ),
              ],
            ),
            
            // Красная полоска индикатора сверху
            Positioned(
              top: 0,
              child: AnimatedContainer(
                height: 3,
                width: 40,
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: isSelected ? accentColor : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(3.5),
                    bottomRight: Radius.circular(3.5),
                  ),
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: accentColor.withOpacity(0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                      offset: const Offset(0, 2),
                    ),
                  ] : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Метод для подписки на обновления назначенных заказов
  void _subscribeToAssignedTasks() {
    final user = AuthService().currentUser;
    if (user == null) return;

    // Отладочная информация о текущем пользователе
    print('ТЕКУЩИЙ ПОЛЬЗОВАТЕЛЬ: ID=${user.uid}, DisplayName=${user.displayName}');

    // Сначала получаем данные инженера для проверки имени
    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get()
        .then((userDoc) {
      // Проверяем, что виджет все еще в дереве
      if (!mounted) return;
      
      String engineerName = "";
      if (userDoc.exists) {
        engineerName = userDoc.data()?['name'] ?? "";
      }
      
      print('Подписка на заказы для инженера: ID=${user.uid}, имя=$engineerName');

      // Отменяем предыдущую подписку если она существует
      _assignedTasksSubscription?.cancel();

      // Подписываемся на обновления заказов, фильтруя по UID инженера
      _assignedTasksSubscription = FirebaseFirestore.instance
          .collection('orders')
          .where('assignedTo', isEqualTo: user.uid) // Строгая фильтрация по UID инженера
          .snapshots()
          .listen((snapshot) {
        // Проверяем, что виджет все еще в дереве
        if (!mounted) return;
        
        print('ДИАГНОСТИКА ЗАКАЗОВ:');
        print('Получено заказов из Firestore для ID=${user.uid}: ${snapshot.docs.length}');
        
        // Проверяем каждый документ подробно
        snapshot.docs.forEach((doc) {
          final docId = doc.id;
          final data = doc.data();
          final String status = data['status'] ?? '';
          
          print('Заказ ID: $docId');
          print('- assignedTo: "${data['assignedTo'] ?? ''}" (ожидается: "${user.uid}")');
          print('- status: "$status"');
        });
            
        // Фильтруем заказы только по статусу (теперь уже точно знаем, что они назначены текущему инженеру)
        final activeOrders = snapshot.docs.where((doc) {
          final data = doc.data();
          final String status = data['status'] ?? '';
          
          // Статусы, которые считаются активными
          final bool hasValidStatus = status.isNotEmpty && 
              ['назначен', 'прибыл', 'в работе', 'принят', 'выехал', 'работает', 'в процессе'].any((s) => status.toLowerCase().contains(s.toLowerCase()));
          
          if (hasValidStatus) {
            print('Заказ ${doc.id} в активном статусе: status=$status');
          }
          
          return hasValidStatus;
        }).toList();
        
        print('ИТОГ: Найдено активных заказов для инженера: ${activeOrders.length}');
        
        if (activeOrders.isEmpty) {
          setState(() {
            _activeTask = null;
          });
          return;
        }

        // Берем первый активный заказ
        final doc = activeOrders.first;
        print('Выбран активный заказ: ${doc.id}');
        final newTask = Task.fromFirestore(doc);

        setState(() {
          _activeTask = newTask;
        });

        // Отменяем предыдущую подписку
        _taskSubscription?.cancel();
        
        // Подписываемся на обновления конкретного заказа
        _taskSubscription = doc.reference.snapshots().listen((taskSnapshot) {
          // Проверяем, что виджет все еще в дереве
          if (!mounted) return;
          
          if (taskSnapshot.exists) {
            setState(() {
              _activeTask = Task.fromFirestore(taskSnapshot);
            });
          } else {
            setState(() {
              _activeTask = null;
            });
          }
        }, onError: (error) {
          print("Ошибка при прослушивании заказа: $error");
        });
      }, onError: (error) {
        print("Ошибка при прослушивании коллекции заказов: $error");
      });
    }).catchError((error) {
      print("Ошибка при получении данных инженера: $error");
    });
  }
}

// Экран доходов инженера
class EngineerIncomeScreen extends StatefulWidget {
  final GlobalKey<_EngineerTasksScreenState> tasksScreenKey;
  
  const EngineerIncomeScreen({super.key, required this.tasksScreenKey});

  @override
  State<EngineerIncomeScreen> createState() => _EngineerIncomeScreenState();
}

class _EngineerIncomeScreenState extends State<EngineerIncomeScreen> with SingleTickerProviderStateMixin {
  bool _isDayMode = true; // По умолчанию выбран режим "День"
  String _currentPeriod = 'День'; // Текст текущего периода
  
  // Анимация диаграммы
  late AnimationController _animationController;
  late Animation<double> _animation;
  int _touchedIndex = -1;
  
  // Списки для хранения всех заказов и заказов истории
  List<IncomeItem> allOrders = [];
  List<IncomeItem> historyOrders = [];
  
  // Подписки на обновления Firestore
  StreamSubscription? _activeOrdersSubscription;
  StreamSubscription? _historyOrdersSubscription;
  
  // Список категорий с их цветами
  final Map<String, Color> categoryColors = {
    'Обслуживание': const Color(0xFFFF5D8F), // Розовый
    'Установка': const Color(0xFF1ED9C4),    // Бирюзовый
    'Ремонт': const Color(0xFFFFB830),       // Оранжевый
    'Консультация': const Color(0xFF8A77FF), // Фиолетовый
    'Гидрант': const Color(0xFF1ED9C4),      // Бирюзовый (как установка)
    'Другое': const Color(0xFF8A77FF),       // Фиолетовый (как консультация)
  };
  
  // Иконки для категорий
  final Map<String, IconData> categoryIcons = {
    'Обслуживание': Icons.build,
    'Установка': Icons.add_circle,
    'Ремонт': Icons.handyman,
    'Консультация': Icons.question_mark,
    'Гидрант': Icons.water_drop,
    'Другое': Icons.category,
  };
  
  // Фильтрованный список заказов
  List<IncomeItem> _filteredOrders = [];
  
  // Выбранные даты для фильтрации
  DateTime? _startDate;
  DateTime? _endDate;
  
  // Состояние открытых карточек
  Map<String, bool> _expandedCards = {};
  
  // Способ сортировки
  SortType _sortType = SortType.dateDesc;
  
  // Индикатор загрузки
  bool _isLoading = true;
  
  // Кэш сервисов и категорий для уменьшения запросов к Firestore
  Map<String, String> _servicesCategoryCache = {};
  Map<String, String> _categoriesNameCache = {};
  bool _categoriesLoaded = false;
  
  @override
  void initState() {
    super.initState();
    // Инициализация данных локализации для русского языка
    initializeDateFormatting('ru', null).then((_) {
      // После инициализации локализации устанавливаем локаль по умолчанию
      Intl.defaultLocale = 'ru';
      
      // Продолжаем инициализацию
      // Сначала инициализируем контроллер анимации
      _animationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800), // Увеличиваем время анимации для более плавного эффекта
      );
      
      _animation = CurvedAnimation(
        parent: _animationController,
        curve: Curves.elasticOut, // Изменяем кривую анимации для эффекта "отскока"
      );
      
      // Затем устанавливаем даты и загружаем реальные заказы
      _startDate = DateTime.now().subtract(const Duration(days: 7));
      _endDate = DateTime.now();
      
      // Загружаем категории перед загрузкой заказов
      _loadCategories().then((_) {
        _loadOrdersFromFirestore();
      });
      
      // Запускаем анимацию
      _animationController.forward();
    });
  }
  
  @override
  void dispose() {
    // Отписываемся от всех подписок Firestore
    _activeOrdersSubscription?.cancel();
    _historyOrdersSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }
  
  // Метод для загрузки заказов из Firestore
  Future<void> _loadOrdersFromFirestore() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final user = AuthService().currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          allOrders = [];
          historyOrders = [];
          _filteredOrders = [];
        });
        return;
      }
      
      // Получаем имя пользователя для проверки поля assignedToName
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      String engineerName = "";
      if (userDoc.exists) {
        engineerName = userDoc.data()?['name'] ?? "";
      }
      
      print('Загрузка доходов для инженера с ID: ${user.uid}, имя: $engineerName');
      
      // Отписываемся от предыдущих подписок
      _activeOrdersSubscription?.cancel();
      _historyOrdersSubscription?.cancel();
      
      // Загружаем активные заказы
      _activeOrdersSubscription = FirebaseFirestore.instance
          .collection('orders')
          .where('assignedTo', isEqualTo: user.uid)
          .orderBy('lastUpdated', descending: true)
          .snapshots()
          .listen((snapshot) {
            List<IncomeItem> orders = [];
            for (var doc in snapshot.docs) {
              try {
                final item = IncomeItem.fromFirestore(doc);
                orders.add(item);
              } catch (e) {
                print('Ошибка при обработке активного заказа ${doc.id}: $e');
              }
            }
            
            setState(() {
              allOrders = [...orders, ...historyOrders];
              _filterOrders();
            });
          }, onError: (error) {
            print('Ошибка при загрузке активных заказов: $error');
          });
      
      // Загружаем заказы из истории
      _historyOrdersSubscription = FirebaseFirestore.instance
          .collection('order_history')
          .where('assignedTo', isEqualTo: user.uid)
          .orderBy('completedAt', descending: true)
          .snapshots()
          .listen((snapshot) {
            List<IncomeItem> orders = [];
            for (var doc in snapshot.docs) {
              try {
                final item = IncomeItem.fromFirestore(doc);
                orders.add(item);
              } catch (e) {
                print('Ошибка при обработке заказа из истории ${doc.id}: $e');
              }
            }
            
            setState(() {
              historyOrders = orders;
              allOrders = [...allOrders.where((o) => 
                  // Фильтруем активные заказы, чтобы удалить те, которые уже есть в истории
                  !historyOrders.any((h) => h.id == o.id || h.id == 'history_${o.id}')), 
                ...historyOrders];
              _filterOrders();
              _isLoading = false;
            });
          }, onError: (error) {
            print('Ошибка при загрузке заказов из истории: $error');
            setState(() {
              _isLoading = false;
            });
          });
    } catch (e) {
      print('Ошибка при загрузке заказов: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Фильтрация и сортировка заказов
  void _filterOrders() {
    setState(() {
      // Фильтрация по датам
      _filteredOrders = allOrders.where((order) {
        // Если даты не выбраны, показываем все
        if (_startDate == null || _endDate == null) return true;
        
        // Проверяем, входит ли дата заказа в выбранный диапазон
        return order.date.isAfter(_startDate!) && 
               order.date.isBefore(_endDate!.add(const Duration(days: 1)));
      }).toList();
      
      // Сортировка
      switch (_sortType) {
        case SortType.dateAsc:
          _filteredOrders.sort((a, b) => a.date.compareTo(b.date));
          break;
        case SortType.dateDesc:
          _filteredOrders.sort((a, b) => b.date.compareTo(a.date));
          break;
        case SortType.amountAsc:
          _filteredOrders.sort((a, b) => a.amount.compareTo(b.amount));
          break;
        case SortType.amountDesc:
          _filteredOrders.sort((a, b) => b.amount.compareTo(a.amount));
          break;
      }
      
      // Перезапускаем анимацию при изменении данных
      _animationController.reset();
      _animationController.forward();
    });
  }
  
  // Подсчет общей суммы
  double get _totalAmount {
    return _filteredOrders.fold(0, (sum, order) => sum + order.amount);
  }
  
  @override
  Widget build(BuildContext context) {
    // Получаем активный заказ из вкладки заданий инженера если он существует
    EngineerTask? activeTask = widget.tasksScreenKey.currentState?._activeTask;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Column(
                children: [
                  // Диаграмма доходов инженера в стиле T-Bank 2025
                  SizedBox(
                    height: 180,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Вырезаем впуклую выемку через ClipPath
                        ClipPath(
                          clipper: ChartNotchClipper(
                            data: _generateChartData(),
                            notchRadius: 22.0,
                          ),
                          child: SfCircularChart(
                            margin: EdgeInsets.zero,
                            series: <DoughnutSeries<_ChartData, String>>[
                              DoughnutSeries<_ChartData, String>(
                                dataSource: _generateChartData(),
                                xValueMapper: (_ChartData data, _) => data.category,
                                yValueMapper: (_ChartData data, _) => data.amount,
                                innerRadius: '85%',
                                radius: '60%',
                                cornerStyle: CornerStyle.bothCurve,
                                pointColorMapper: (_ChartData data, _) => categoryColors[data.category] ?? Colors.grey,
                                dataLabelMapper: (_ChartData data, _) {
                                  final total = _filteredOrders.fold(0.0, (sum, o) => sum + o.amount);
                                  return total > 0 ? '${(data.amount / total * 100).round()}%' : '';
                                },
                                dataLabelSettings: DataLabelSettings(
                                  isVisible: true,
                                  labelPosition: ChartDataLabelPosition.outside,
                                  connectorLineSettings: ConnectorLineSettings(
                                    type: ConnectorType.curve,
                                    length: '15%',
                                    width: 2,
                                    color: Colors.grey,
                                  ),
                                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                            annotations: <CircularChartAnnotation>[
                              CircularChartAnnotation(
                                widget: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_totalAmount.toStringAsFixed(0), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                    const Text('₽', style: TextStyle(fontSize: 12, color: Colors.black54)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ), // SfCircularChart закрывается внутри ClipPath
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24), // Увеличиваю отступ между диаграммой и категориями
                  
                  // Список категорий с суммами в стиле блоков с обводкой
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: _buildCategoryIncomeList(),
                  ),
                  
                  const SizedBox(height: 16), // Увеличиваю отступ после категорий
                  
                  // Сортировка и фильтры
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      InkWell(
                        onTap: () => _selectDateRange(context),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: Color(0xFFD04E4E)),
                            const SizedBox(width: 4),
                            const Text(
                              'Выбрать даты',
                              style: TextStyle(
                                color: Color(0xFFD04E4E),
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () => _showSortOptions(context),
                        child: Row(
                          children: [
                            const Text(
                              'Сортировка',
                              style: TextStyle(
                                color: Color(0xFFD04E4E),
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.sort, size: 16, color: Color(0xFFD04E4E)),
                          ],
                        ),
                      ),
                    ],
                  ),
               
                  // Текущий активный заказ (новый блок)
                  if (activeTask != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2D2D),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD04E4E).withOpacity(0.3))
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Заказ №${activeTask.id}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: activeTask.status == TaskStatus.pending 
                                      ? Colors.orange.withOpacity(0.2) 
                                      : Colors.green.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  activeTask.status == TaskStatus.pending ? 'Назначен' : 'В процессе',
                                  style: TextStyle(
                                    color: activeTask.status == TaskStatus.pending ? Colors.orange : Colors.green,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            activeTask.address,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Клиент: ${activeTask.clientName}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${activeTask.cost.toStringAsFixed(2)} ₽',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFD04E4E),
                                ),
                              ),
                              if (activeTask.status == TaskStatus.pending)
                                ElevatedButton(
                                  onPressed: () {
                                    // Переключаемся на вкладку заявок
                                    final mainScreenState = context.findAncestorStateOfType<_EngineerMainScreenState>();
                                    if (mainScreenState != null) {
                                      mainScreenState._selectedIndex = 1;
                                      mainScreenState._pageController.animateToPage(
                                        1,
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeOut,
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFD04E4E),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('Перейти к заказу'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Карточка "Все заказы"
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Все заказы',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_filteredOrders.length} шт. на ${_totalAmount.toStringAsFixed(0)} ₽',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Список отдельных заказов
            Expanded(
              child: _filteredOrders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 64,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Нет заказов за выбранный период',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadOrdersFromFirestore,
                      color: const Color(0xFFD04E4E),
                      child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filteredOrders.length,
                      itemBuilder: (context, index) {
                        final order = _filteredOrders[index];
                        final isExpanded = _expandedCards[order.id] ?? false;
                          return _buildOrderCard(order, isExpanded);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Обновляю метод _buildDetailRow для более гибкого отображения деталей заказа и избежания переполнения
  Widget _buildDetailRow(String label, String value, IconData icon, {Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.grey[400],
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[400],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: textColor ?? Colors.white,
                fontWeight: FontWeight.w400,
              ),
              overflow: TextOverflow.visible,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
  
  // Обновленный метод для отображения карточки заказа с реальными данными
  Widget _buildOrderCard(IncomeItem order, bool isExpanded) {
    final Color categoryColor = _getCategoryColor(order.category);
    final IconData categoryIcon = _getCategoryIcon(order.category);
    
    // Сокращаем идентификатор заказа для отображения
    final String shortOrderId = order.id.length > 8 
        ? '${order.id.substring(0, 8)}...'
        : order.id;
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                          color: const Color(0xFF2D2D2D),
                          child: InkWell(
                            onTap: () => _toggleCardExpanded(order.id),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Заголовок заказа
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                  Expanded(
                    child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(5),
                                            decoration: BoxDecoration(
                                              color: order.completed 
                                                  ? Colors.green 
                                                  : Colors.orange,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              order.completed
                                                  ? Icons.done
                                                  : Icons.schedule,
                                              color: Colors.white,
                                              size: 12,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Заказ №$shortOrderId',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                    ),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            '${order.amount.toStringAsFixed(0)} ₽',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                          color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          AnimatedRotation(
                                            turns: isExpanded ? 0.5 : 0,
                                            duration: const Duration(milliseconds: 200),
                                            child: const Icon(
                                              Icons.keyboard_arrow_down,
                                              color: Colors.grey,
                                              size: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  
                                  // Дата заказа в компактном виде
                                  if (!isExpanded)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 30, top: 4),
                                      child: Text(
                                        '${order.date.day}.${order.date.month}.${order.date.year}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[400],
                                        ),
                                      ),
                                    ),
                                  
                                  // Детали заказа в развернутом виде
                                  if (isExpanded)
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Divider(),
                                          _buildDetailRow(
                                            'Дата', 
                                            '${order.date.day}.${order.date.month}.${order.date.year}',
                                            Icons.calendar_today,
                                          ),
                                          _buildDetailRow(
                                            'Категория', 
                        _getCategory(order.category),
                        categoryIcon,
                        textColor: categoryColor,
                                          ),
                                          _buildDetailRow(
                                            'Адрес', 
                                            order.address,
                                            Icons.location_on,
                                          ),
                                          _buildDetailRow(
                                            'Клиент', 
                                            order.clientName,
                                            Icons.person,
                                          ),
                                          _buildDetailRow(
                                            'Описание', 
                                            order.description,
                                            Icons.info_outline,
                                          ),
                                          _buildDetailRow(
                                            'Статус', 
                        order.completed ? 'Выполнен' : order.status.isEmpty ? 'В процессе' : order.status,
                                            Icons.check_circle_outline,
                                            textColor: order.completed ? Colors.green : Colors.orange,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
  }
  
  // Выбор диапазона дат
  Future<void> _selectDateRange(BuildContext context) async {
    // Временные переменные для выбора
    DateTime tempStart = _startDate ?? DateTime.now().subtract(const Duration(days: 7));
    DateTime tempEnd = _endDate ?? DateTime.now();
    
    // Переменная для отслеживания отображаемого месяца
    DateTime displayMonth = DateTime.now();
    // Контроллер для календаря
    final dp.DateRangePickerController calendarController = dp.DateRangePickerController();
    
    // Показываем кастомное меню внизу
    final picked = await showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          // Метод для переключения месяца (вперед/назад)
          void changeMonth(int months) {
            setModalState(() {
              displayMonth = DateTime(displayMonth.year, displayMonth.month + months);
              calendarController.displayDate = displayMonth;
            });
          }
          
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.7,
            decoration: const BoxDecoration(
            color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                // Заголовок
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Text('Выберите диапазон', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop(DateTimeRange(start: tempStart, end: tempEnd));
                        },
                        child: const Text('Сохранить', style: TextStyle(color: Color(0xFFD04E4E), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
                ),
                // Показываем текущий диапазон
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    '${_formatDate(tempStart)} – ${_formatDate(tempEnd)}',
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),
                // Заголовок с днями недели
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
                      Text('ПН', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text('ВТ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text('СР', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text('ЧТ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text('ПТ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text('СБ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red)),
                      Text('ВС', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Селектор диапазона
                Expanded(
                  child: Theme(
                    data: ThemeData.light().copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: Color(0xFFD04E4E),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Кастомный заголовок месяца и года с кнопками навигации
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Кнопка предыдущего месяца
                              IconButton(
                                icon: const Icon(Icons.chevron_left, color: Color(0xFFD04E4E)),
                                onPressed: () => changeMonth(-1),
                              ),
                              // Название месяца и год
              Text(
                                DateFormat('MMMM yyyy', 'ru').format(displayMonth),
                                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                ),
              ),
                              // Кнопка следующего месяца
                              IconButton(
                                icon: const Icon(Icons.chevron_right, color: Color(0xFFD04E4E)),
                                onPressed: () => changeMonth(1),
              ),
            ],
          ),
        ),
                        
                        Expanded(
                          child: dp.SfDateRangePicker(
                            controller: calendarController,
                            selectionMode: dp.DateRangePickerSelectionMode.range,
                            initialSelectedRange: dp.PickerDateRange(tempStart, tempEnd),
                            initialDisplayDate: displayMonth,
                            confirmText: 'Сохранить', 
                            cancelText: 'Отмена',
                            headerHeight: 0, // Скрываем стандартный заголовок
                            monthViewSettings: const dp.DateRangePickerMonthViewSettings(
                              firstDayOfWeek: 1,
                              showWeekNumber: false,
                              viewHeaderHeight: 0,  // Скрываем стандартные заголовки дней недели
                            ),
                            selectionColor: const Color(0xFFD04E4E),
                            startRangeSelectionColor: const Color(0xFFD04E4E),
                            endRangeSelectionColor: const Color(0xFFD04E4E),
                            rangeSelectionColor: const Color(0xFFD04E4E).withOpacity(0.2),
                            selectionTextStyle: const TextStyle(color: Colors.white),
                            onSelectionChanged: (args) {
                              if (args.value is dp.PickerDateRange) {
                                final range = args.value as dp.PickerDateRange;
                                // Безопасно обновляем диапазон: если значения null, оставляем предыдущие
                                tempStart = range.startDate ?? tempStart;
                                tempEnd = range.endDate ?? tempEnd;
                              }
                            },
                            onViewChanged: (dp.DateRangePickerViewChangedArgs args) {
                              if (args.visibleDateRange.startDate != null) {
                                // Используем addPostFrameCallback для отложенного обновления
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted) {
                                    setModalState(() {
                                      displayMonth = args.visibleDateRange.startDate!;
                                    });
                                  }
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
    // Если пользователь сохранил диапазон
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        // Обновляем текст периода
        if (_startDate == _endDate) {
          _currentPeriod = _formatDate(_startDate!);
          _isDayMode = true;
        } else {
          _currentPeriod = '${_formatDate(_startDate!)} – ${_formatDate(_endDate!)}';
          _isDayMode = false;
        }
        _filterOrders();
      });
    }
  }
  
  // Форматирование даты
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
  
  // Вспомогательный метод для парсинга дат в формате DD.MM.YYYY
  DateTime _parseDate(String dateStr) {
    try {
      // Если дата в формате "Дата не указана" или другом некорректном формате
      if (dateStr == 'Дата не указана' || dateStr.isEmpty) {
        return DateTime(1970);  // Возвращаем старую дату
      }
      
      // Разбиваем строку по разделителю
      final parts = dateStr.split('.');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
      
      // Если формат не соответствует ожидаемому, возвращаем текущую дату
      return DateTime.now();
    } catch (e) {
      print('Ошибка при парсинге даты "$dateStr": $e');
      return DateTime.now();
    }
  }
  
  // Быстрый выбор периода
  void _setQuickPeriod(String period) {
    setState(() {
      switch (period) {
        case 'День':
          _startDate = DateTime.now();
          _endDate = DateTime.now();
          _isDayMode = true;
          _currentPeriod = 'День';
            break;
        case 'Неделя':
          _startDate = DateTime.now().subtract(const Duration(days: 7));
          _endDate = DateTime.now();
          _isDayMode = false;
          _currentPeriod = 'Неделя';
          break;
        case 'Месяц':
          _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
          _endDate = DateTime.now();
          _isDayMode = false;
          _currentPeriod = 'Месяц';
            break;
          case 'Год':
          _startDate = DateTime(DateTime.now().year, 1, 1);
          _endDate = DateTime.now();
          _isDayMode = false;
          _currentPeriod = 'Год';
            break;
      }
      _filterOrders();
    });
  }
  
  // Переключение состояния раскрытой карточки
  void _toggleCardExpanded(String id) {
    setState(() {
      _expandedCards[id] = !(_expandedCards[id] ?? false);
    });
  }
  
  // Изменение способа сортировки
  void _changeSortType(SortType type) {
    setState(() {
      _sortType = type;
      _filterOrders();
    });
  }
  
  // Генерация данных для Syncfusion DoughnutChart из реальных данных
  List<_ChartData> _generateChartData() {
    Map<String, double> categoryAmounts = {};
    
    // Собираем суммы по категориям из отфильтрованных заказов
    for (var order in _filteredOrders) {
      // Нормализуем название категории для объединения похожих категорий
      String normalizedCategory = _getCategory(order.category);
      
      // Добавляем или обновляем сумму для этой категории
      categoryAmounts[normalizedCategory] = (categoryAmounts[normalizedCategory] ?? 0) + order.amount;
    }
    
    // Преобразуем данные в формат для диаграммы
    return categoryAmounts.entries
        .map((e) => _ChartData(e.key, e.value))
        .toList();
  }
  
  // Метод для нормализации названий категорий
  String _getCategory(String serviceTitle) {
    // Отладочная информация для диагностики
    print('Определение категории для услуги: "$serviceTitle"');
    
    // Если сервис не указан, возвращаем "Другое"
    if (serviceTitle.isEmpty || serviceTitle == 'Не указана') {
      print('Пустое название услуги, возвращаем категорию "Другое"');
      return 'Другое';
    }
    
    // Убедимся, что категории загружены
    if (!_categoriesLoaded) {
      print('Категории не загружены, используем резервный метод');
      return _fallbackCategoryNormalization(serviceTitle);
    }
    
    try {
      // Приводим название услуги к нижнему регистру для поиска
      final title = serviceTitle.toLowerCase().trim();
      print('Нормализованное название услуги: "$title"');
      
      // Шаг 1: Проверяем, есть ли точное совпадение названия услуги
      if (_servicesCategoryCache.containsKey(title)) {
        final categoryId = _servicesCategoryCache[title]!;
        print('Найдено точное совпадение, categoryId = $categoryId');
        
        // Получаем название категории по ID
        if (_categoriesNameCache.containsKey(categoryId)) {
          final categoryName = _categoriesNameCache[categoryId]!;
          print('Определена категория по точному совпадению: "$categoryName"');
          return categoryName;
        } else {
          // Если категории нет в кэше, запрашиваем ее напрямую из Firestore
          print('Категория с ID $categoryId не найдена в кэше, запрашиваем из Firestore');
          
          // Запрашиваем категорию напрямую (но возвращаем временное значение пока запрос выполняется)
          _loadCategoryNameFromFirestore(categoryId);
          
          // Возвращаем временное значение (если в будущем хотим сделать ожидание, то это место нужно изменить)
          return 'Загрузка...';
        }
      }
      
      // Шаг 2: Ищем частичное совпадение в названиях услуг
      List<MapEntry<String, String>> matchedServices = [];
      
      for (final entry in _servicesCategoryCache.entries) {
        final serviceName = entry.key;
        final categoryId = entry.value;
        
        // Если название услуги содержит текущее название или наоборот
        if (title.contains(serviceName) || serviceName.contains(title)) {
          // Получаем название категории по ID
          if (_categoriesNameCache.containsKey(categoryId)) {
            matchedServices.add(
              MapEntry(serviceName, categoryId)
            );
          }
        }
      }
      
      // Если нашли частичные совпадения, берем самое длинное совпадение
      if (matchedServices.isNotEmpty) {
        // Сортируем по длине названия услуги (более длинные названия имеют приоритет)
        matchedServices.sort((a, b) => b.key.length.compareTo(a.key.length));
        final bestMatch = matchedServices.first;
        final categoryName = _categoriesNameCache[bestMatch.value]!;
        print('Определена категория по частичному совпадению: "$categoryName"');
        return categoryName;
      }
      
      // Шаг 3: Если ничего не нашли, используем резервный метод
      print('Категория не найдена в базе, используем резервный метод');
      return _fallbackCategoryNormalization(serviceTitle);
    } catch (e) {
      print('Ошибка при определении категории: $e');
      return _fallbackCategoryNormalization(serviceTitle);
    }
  }
  
  // Метод для загрузки названия категории напрямую из Firestore
  Future<void> _loadCategoryNameFromFirestore(String categoryId) async {
    try {
      print('Запрашиваем категорию с ID $categoryId напрямую из Firestore');
      
      final categoryDoc = await FirebaseFirestore.instance
          .collection('services_categories')  // Исправлено: было services_categories
          .doc(categoryId)
          .get();
      
      print('Получен документ категории: ${categoryDoc.id}, существует: ${categoryDoc.exists}');
      
      if (categoryDoc.exists) {
        final data = categoryDoc.data();
        print('Данные категории: ${data.toString()}');
        
        if (data != null) {
          // Проверяем все возможные поля, которые могут содержать имя категории
          String? categoryName;
          
          if (data['name'] != null) {
            categoryName = data['name'] as String;
          } else if (data['title'] != null) {
            categoryName = data['title'] as String;
          } else if (data['category'] != null) {
            categoryName = data['category'] as String;
          }
          
          if (categoryName != null && categoryName.isNotEmpty) {
            print('Загружена категория с ID $categoryId: "$categoryName"');
            
            // Сохраняем категорию в кэш
            _categoriesNameCache[categoryId] = categoryName;
            
            // Перестраиваем UI
            if (mounted) {
              setState(() {});
            }
          } else {
            print('Категория с ID $categoryId не содержит подходящего поля для имени');
            _categoriesNameCache[categoryId] = 'Категория $categoryId';
          }
        } else {
          print('Категория с ID $categoryId не содержит данных');
        }
      } else {
        print('Категория с ID $categoryId не найдена в Firestore');
      }
    } catch (e) {
      print('Ошибка при загрузке категории $categoryId: $e');
    }
  }
  
  // Резервный метод нормализации категории на основе ключевых слов
  String _fallbackCategoryNormalization(String category) {
    // Приводим к нижнему регистру для удобства сравнения
    final lowerCategory = category.toLowerCase();
    
    // Проверяем на ключевые слова для определения категории
    if (lowerCategory.contains('обслуж') || lowerCategory.contains('сервис')) {
      return 'Обслуживание';
    } else if (lowerCategory.contains('установ') || lowerCategory.contains('монтаж')) {
      return 'Установка';
    } else if (lowerCategory.contains('ремонт') || lowerCategory.contains('починк')) {
      return 'Ремонт';
    } else if (lowerCategory.contains('консульт') || lowerCategory.contains('осмотр')) {
      return 'Консультация';
    } else if (lowerCategory.contains('гидрант')) {
      return 'Гидрант';
    } else {
      return 'Другое';
    }
  }
  
  // Метод для получения цвета категории с дополнительной проверкой
  Color _getCategoryColor(String category) {
    final normalizedCategory = _getCategory(category);
    return categoryColors[normalizedCategory] ?? const Color(0xFF8A77FF); // Фиолетовый по умолчанию
  }
  
  // Метод для получения иконки категории с дополнительной проверкой
  IconData _getCategoryIcon(String category) {
    final normalizedCategory = _getCategory(category);
    return categoryIcons[normalizedCategory] ?? Icons.category; // Иконка категории по умолчанию
  }

  // Метод для построения списка категорий доходов с реальными данными
  Widget _buildCategoryIncomeList() {
    // Создаем Map для хранения суммы по каждой категории
    final Map<String, double> categoryTotals = {};
    
    // Вычисляем сумму для каждой категории
    for (var order in _filteredOrders) {
      final normalizedCategory = _getCategory(order.category);
      categoryTotals[normalizedCategory] = (categoryTotals[normalizedCategory] ?? 0) + order.amount;
    }
    
    // Если категорий нет, показываем сообщение
    if (categoryTotals.isEmpty) {
      return const Center(
        child: Text(
          'Нет данных о категориях доходов за выбранный период',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    
    // Создаем список категорий для отображения
    return Column(
      children: categoryTotals.entries.map((entry) {
        final category = entry.key;
        final amount = entry.value;
        final percentage = _totalAmount > 0 
          ? (amount / _totalAmount * 100).toStringAsFixed(0) 
          : '0';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: categoryColors[category] ?? Colors.grey,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Иконка категории
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (categoryColors[category] ?? Colors.grey).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  categoryIcons[category] ?? Icons.category,
                  color: categoryColors[category] ?? Colors.grey,
                  size: 18,
              ),
              ),
              const SizedBox(width: 12),
              // Название категории
              Expanded(
                child: Text(
                  category,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              // Процент
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (categoryColors[category] ?? Colors.grey).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$percentage%',
                  style: TextStyle(
                    color: categoryColors[category] ?? Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Сумма
              Text(
                '${amount.toStringAsFixed(0)} ₽',
                style: TextStyle(
                  color: categoryColors[category] ?? Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
  
  // Отображение диалога с опциями сортировки
  void _showSortOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Сортировка',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const Divider(),
              _buildSortOption(
                ctx,
                'По дате (сначала новые)',
                SortType.dateDesc,
              ),
              _buildSortOption(
                ctx,
                'По дате (сначала старые)',
                SortType.dateAsc,
              ),
              _buildSortOption(
                ctx,
                'По сумме (по возрастанию)',
                SortType.amountAsc,
              ),
              _buildSortOption(
                ctx,
                'По сумме (по убыванию)',
                SortType.amountDesc,
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
  
  // Вспомогательный метод для опции сортировки
  Widget _buildSortOption(BuildContext context, String title, SortType type) {
    return InkWell(
      onTap: () {
        _changeSortType(type);
        Navigator.pop(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
            Text(
              title,
                  style: TextStyle(
                fontSize: 16,
                color: _sortType == type ? const Color(0xFFD04E4E) : Colors.black,
                fontWeight: _sortType == type ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (_sortType == type)
              const Icon(
                Icons.check,
                color: Color(0xFFD04E4E),
              ),
          ],
        ),
      ),
    );
  }
  
  // Метод для загрузки категорий из Firestore
  Future<void> _loadCategories() async {
    try {
      print('Загрузка категорий из Firestore...');
      
      // Сначала очищаем кэши, чтобы избежать устаревших данных
      _servicesCategoryCache.clear();
      _categoriesNameCache.clear();
      
      // Загружаем соответствие услуг и категорий
      final servicesSnapshot = await FirebaseFirestore.instance
          .collection('services')
          .get();
      
      print('Загружено услуг: ${servicesSnapshot.docs.length}');
      
      for (final doc in servicesSnapshot.docs) {
        final data = doc.data();
        final String title = data['title'] ?? '';
        final String categoryId = data['categoryId'] ?? '';
        
        print('Обработка услуги: id=${doc.id}, title=$title, categoryId=$categoryId');
        
        if (title.isNotEmpty && categoryId.isNotEmpty) {
          _servicesCategoryCache[title.toLowerCase()] = categoryId;
        }
      }
      
      print('Загружено сопоставлений услуг и категорий: ${_servicesCategoryCache.length}');
      
      // Загружаем категории
      final categoriesSnapshot = await FirebaseFirestore.instance
          .collection('service_categories')  // Исправлено: было services_categories
          .get();
      
      print('Загружено документов categories: ${categoriesSnapshot.docs.length}');
      
      for (final doc in categoriesSnapshot.docs) {
        final data = doc.data();
        print('Категория ${doc.id}: ${data.toString()}');
        
        final String categoryName = data['name'] ?? '';
        
        if (categoryName.isNotEmpty) {
          print('Сохраняем категорию ${doc.id} с именем $categoryName');
          _categoriesNameCache[doc.id] = categoryName;
        } else {
          print('Категория ${doc.id} не имеет поля name или оно пустое: ${data.toString()}');
        }
      }
      
      print('Загружено категорий: ${_categoriesNameCache.length}');
      
      // Выводим содержимое кэшей для диагностики
      print('--- Содержимое кэша услуг ---');
      _servicesCategoryCache.forEach((key, value) {
        print('Услуга: "$key" -> CategoryID: "$value"');
      });
      
      print('--- Содержимое кэша категорий ---');
      _categoriesNameCache.forEach((key, value) {
        print('CategoryID: "$key" -> Название: "$value"');
      });
      
      // Проверяем наличие конкретной категории
      if (_categoriesNameCache.containsKey('MpEM9cBuiHBwg1cjQhcR')) {
        print('Категория MpEM9cBuiHBwg1cjQhcR найдена: ${_categoriesNameCache['MpEM9cBuiHBwg1cjQhcR']}');
      } else {
        print('Категория MpEM9cBuiHBwg1cjQhcR НЕ найдена в кэше');
        
        // Попробуем загрузить ее напрямую
        await _loadCategoryNameFromFirestore('MpEM9cBuiHBwg1cjQhcR');
      }
      
      _categoriesLoaded = true;
      
      // Обновляем UI после загрузки
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Ошибка при загрузке категорий: $e');
      _categoriesLoaded = false;
    }
  }
}

// Модель данных для Syncfusion диаграммы
class _ChartData {
  final String category;
  final double amount;
  _ChartData(this.category, this.amount);
}

// Кастомный клиппер для вырезания впуклой выемки на диagrama
class ChartNotchClipper extends CustomClipper<Path> {
  final List<_ChartData> data;
  final double notchRadius;
  ChartNotchClipper({required this.data, required this.notchRadius});
  @override
  Path getClip(Size size) {
    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    if (data.length >= 2) {
      final total = data.fold(0.0, (sum, e) => sum + e.amount);
      final sweep = data[0].amount / total * 2 * pi;
      final angle = -pi / 2 + sweep;
      final innerR = size.width * 0.7 / 2;
      final outerR = size.width * 0.9 / 2;
      final radius = (innerR + outerR) / 2;
      final center = Offset(size.width / 2, size.height / 2);
      final notchCenter = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      path.addOval(Rect.fromCircle(center: notchCenter, radius: notchRadius));
    }
    path.fillType = PathFillType.evenOdd;
    return path;
  }
  @override
  bool shouldReclip(covariant ChartNotchClipper old) => true;
}

// Перечисление типов сортировки
enum SortType {
  dateAsc,
  dateDesc,
  amountAsc,
  amountDesc,
}

// Модель элемента дохода
class IncomeItem {
  final String id;
  final double amount;
  final DateTime date;
  final String address;
  final String clientName;
  final String description;
  final bool completed;
  final String category;
  final String status;

  IncomeItem({
    required this.id,
    required this.amount,
    required this.date,
    required this.address,
    required this.clientName,
    required this.description,
    required this.completed,
    required this.category,
    required this.status,
  });

  // Фабричный метод для создания объекта из Firestore документа
  factory IncomeItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Определяем дату заказа
    DateTime orderDate;
    if (data['completedAt'] != null) {
      orderDate = (data['completedAt'] as Timestamp).toDate();
    } else if (data['createdAt'] != null) {
      orderDate = (data['createdAt'] as Timestamp).toDate();
    } else if (data['lastUpdated'] != null) {
      orderDate = (data['lastUpdated'] as Timestamp).toDate();
    } else {
      orderDate = DateTime.now();
    }
    
    // Определяем название услуги для дальнейшего определения категории
    String serviceTitle = data['title'] ?? '';
    if (serviceTitle.isEmpty) {
      serviceTitle = data['service'] ?? 'Не указана';
    }
    
    // Определяем статус и завершенность заказа
    final String status = data['status'] ?? '';
    final bool isCompleted = status == 'выполнен';
    
    return IncomeItem(
      id: doc.id,
      amount: data['price'] is num ? (data['price'] as num).toDouble() : 0.0,
      date: orderDate,
      address: data['address'] ?? 'Адрес не указан',
      clientName: data['userName'] ?? data['clientName'] ?? 'Клиент не указан',
      description: data['additionalInfo'] ?? data['description'] ?? 'Нет описания',
      completed: isCompleted,
      category: serviceTitle, // Сохраняем оригинальное название услуги
      status: status,
    );
  }
}

// Экран истории заказов инженера
class EngineerHistoryScreen extends StatefulWidget {
  const EngineerHistoryScreen({super.key});

  @override
  State<EngineerHistoryScreen> createState() => _EngineerHistoryScreenState();
}

class _EngineerHistoryScreenState extends State<EngineerHistoryScreen> {
  // Состояние открытых карточек
  Map<String, bool> _expandedCards = {};
  
  // Данные истории заказов
  List<HistoryItem> historyItems = [];
  bool _isLoading = true;
  StreamSubscription? _historySubscription;
  
  @override
  void initState() {
    super.initState();
    _loadHistory();
  }
  
  @override
  void dispose() {
    _historySubscription?.cancel();
    super.dispose();
  }
  
  // Загрузка истории заказов из Firestore
  Future<void> _loadHistory() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });
    
    final user = AuthService().currentUser;
    if (user == null) {
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
      return;
    }
    
    print('==== ЗАГРУЗКА ИСТОРИИ ЗАКАЗОВ ИНЖЕНЕРА ====');
    print('Текущий пользователь: ID=${user.uid}, DisplayName=${user.displayName}');
    
    try {
      // Отменяем предыдущую подписку
      _historySubscription?.cancel();
      
      // Создаем список для хранения всех элементов истории
      List<HistoryItem> allHistoryItems = [];
      
      // 1. Сначала проверяем основную коллекцию orders на заказы со статусом "выполнен" или "отменен"
      final ordersSnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('assignedTo', isEqualTo: user.uid) // Строгое соответствие по UID инженера
          .where('status', whereIn: ['выполнен', 'отменен']) // Только выполненные или отмененные заказы
          .get();
          
      print('Найдено выполненных/отмененных заказов в коллекции orders с ID=${user.uid}: ${ordersSnapshot.docs.length}');
      
      // Преобразуем заказы из основной коллекции
      for (var doc in ordersSnapshot.docs) {
        final data = doc.data();
        final String status = data['status'] ?? '';
        
        print('Найден заказ для инженера: ${doc.id}, статус: $status');
        
        // Преобразуем заказ в элемент истории
        final completedAt = data['completedAt'] != null ? 
            (data['completedAt'] as Timestamp).toDate() : 
            DateTime.now();
          
        allHistoryItems.add(HistoryItem(
          id: doc.id,
          clientName: data['userName'] ?? data['clientName'] ?? 'Неизвестный клиент',
          service: data['title'] ?? 'Услуга не указана',
          address: data['address'] ?? 'Адрес не указан',
          status: status == 'выполнен' ? 'Выполнено' : 'Отменено',
          price: data['price'] is num ? (data['price'] as num).toDouble() : 0.0,
          date: '${completedAt.day.toString().padLeft(2, '0')}.${completedAt.month.toString().padLeft(2, '0')}.${completedAt.year}',
        ));
      }
      
      // 2. Затем проверяем коллекцию order_history
      final historySnapshot = await FirebaseFirestore.instance
          .collection('order_history')
          .where('assignedTo', isEqualTo: user.uid) // Строгое соответствие по UID инженера
          .orderBy('completedAt', descending: true)
          .limit(100)
          .get();
      
      print('Найдено записей в коллекции order_history для ID=${user.uid}: ${historySnapshot.docs.length}');
      
      // Преобразуем записи из коллекции истории
      for (var doc in historySnapshot.docs) {
        final data = doc.data();
        final String status = data['status'] ?? '';
        
        // Добавляем только записи со статусом "выполнен" или "отменен"
        if (status == 'выполнен' || status == 'отменен') {
          print('Найдена запись истории для инженера: ${doc.id}, статус: $status');
          
          final completedAt = data['completedAt'] != null ? 
              (data['completedAt'] as Timestamp).toDate() : 
              null;
              
          final dateStr = completedAt != null ? 
              '${completedAt.day.toString().padLeft(2, '0')}.${completedAt.month.toString().padLeft(2, '0')}.${completedAt.year}' : 
              'Дата не указана';
          
          // Добавляем запись в общий список
          allHistoryItems.add(HistoryItem(
            id: doc.id,
            clientName: data['userName'] ?? data['clientName'] ?? 'Неизвестный клиент',
            service: data['title'] ?? 'Услуга не указана',
            address: data['address'] ?? 'Адрес не указан',
            status: status == 'выполнен' ? 'Выполнено' : 'Отменено',
            price: data['price'] is num ? (data['price'] as num).toDouble() : 0.0,
            date: dateStr,
          ));
        }
      }
      
      // Сортируем все элементы по убыванию даты (самые последние - первые)
      allHistoryItems.sort((a, b) {
        try {
          // Преобразуем строковые даты в объекты DateTime для корректного сравнения
          final dateA = _parseDate(a.date);
          final dateB = _parseDate(b.date);
          return dateB.compareTo(dateA);  // Сравниваем в обратном порядке
        } catch (e) {
          return 0;  // В случае ошибки парсинга считаем даты равными
        }
      });
      
      print('Всего элементов истории после объединения: ${allHistoryItems.length}');
      
      // Обновляем UI с объединенным списком истории
      setState(() {
        historyItems = allHistoryItems;
        _isLoading = false;
      });
    } catch (e) {
      print('Ошибка при загрузке истории: $e');
      if (!mounted) return;
      
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Вспомогательный метод для парсинга дат в формате DD.MM.YYYY
  DateTime _parseDate(String dateStr) {
    try {
      // Если дата в формате "Дата не указана" или другом некорректном формате
      if (dateStr == 'Дата не указана' || dateStr.isEmpty) {
        return DateTime(1970);  // Возвращаем старую дату
      }
      
      // Разбиваем строку по разделителю
      final parts = dateStr.split('.');
      if (parts.length == 3) {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        return DateTime(year, month, day);
      }
      
      // Если формат не соответствует ожидаемому, возвращаем текущую дату
      return DateTime.now();
    } catch (e) {
      print('Ошибка при парсинге даты "$dateStr": $e');
      return DateTime.now();
    }
  }
  
  // Переключение состояния раскрытой карточки
  void _toggleCardExpanded(String id) {
    if (!mounted) return;
    
    setState(() {
      _expandedCards[id] = !(_expandedCards[id] ?? false);
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
    
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadHistory,
          color: const Color(0xFFD04E4E),
        child: historyItems.isEmpty
            ? _buildEmptyHistoryView()
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: historyItems.length,
                itemBuilder: (context, index) {
                  final item = historyItems[index];
                  final isExpanded = _expandedCards[item.id + item.date] ?? false;
                  return _buildHistoryCard(item, isExpanded, index);
                },
                ),
              ),
      ),
    );
  }
  
  Widget _buildEmptyHistoryView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'lib/assets/sad_red_gid.gif',
            width: 200,
            height: 200,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 20),
          const Text(
            'История заказов пуста',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHistoryCard(HistoryItem item, bool isExpanded, int index) {
    final bool isCompleted = item.status == 'Выполнено';
    final Color statusColor = isCompleted ? Colors.green : Colors.red;
    
    // Сокращаем ID заказа для более компактного отображения
    final String shortId = item.id.length > 8 
        ? item.id.substring(0, 8) + '...' 
        : item.id;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _toggleCardExpanded(item.id + item.date),
            borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
            // Заголовок заказа (всегда виден)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isCompleted ? const Color(0xFFE8F5E9) : const Color(0xFFFBE9E7),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                  bottomLeft: isExpanded ? Radius.zero : Radius.circular(12),
                  bottomRight: isExpanded ? Radius.zero : Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isCompleted ? Icons.check_circle : Icons.cancel,
                      color: statusColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                          "Заказ №$shortId",
                                style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                                ),
                              ),
                        const SizedBox(height: 2),
                              Text(
                          item.date,
                                style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                                  Row(
                                    children: [
                                      Text(
                        "${item.price.toStringAsFixed(1)} ₽",
                                        style: TextStyle(
                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: statusColor,
                                        ),
                                      ),
                      const SizedBox(width: 8),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
            
            // Детали заказа (видны только при развороте)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: isExpanded ? null : 0,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: isExpanded 
                ? Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildDetailRow(
                          Icons.person, 
                          'Клиент', 
                          item.clientName,
                        ),
                        _buildDetailRow(
                          Icons.home_repair_service, 
                          'Услуга', 
                          item.service,
                        ),
                        _buildDetailRow(
                          Icons.location_on, 
                          'Адрес', 
                          item.address,
                        ),
                        _buildDetailRow(
                          Icons.assignment_turned_in, 
                          'Статус', 
                          item.status,
                          valueColor: statusColor,
                        ),
                        _buildDetailRow(
                          Icons.attach_money, 
                          'Стоимость', 
                          "${item.price.toStringAsFixed(1)} ₽",
                          valueColor: statusColor,
                        ),
                      ],
                    ),
                  )
                : const SizedBox(),
                    ),
                  ],
                ),
      ),
    );
  }
  
  // Вспомогательный метод для построения строки с деталями
  Widget _buildDetailRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
          Icon(
            icon,
            size: 18,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(
              label + ":",
                          style: TextStyle(
                            fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
                          style: TextStyle(
                            fontSize: 14,
                color: valueColor ?? Colors.black87,
                fontWeight: valueColor != null ? FontWeight.w500 : FontWeight.normal,
              ),
              overflow: TextOverflow.visible,
              softWrap: true,
                          ),
                        ),
                      ],
      ),
    );
  }

  
}

// Модель элемента истории
class HistoryItem {
  final String id;
  final String clientName;
  final String service;
  final String address;
  final String status;
  final double price;
  final String date;

  HistoryItem({
    required this.id,
    required this.clientName,
    required this.service,
    required this.address,
    required this.status,
    required this.price,
    required this.date,
  });
}

// Экран заданий инженера
class EngineerTasksScreen extends StatefulWidget {
  const EngineerTasksScreen({super.key});

  @override
  State<EngineerTasksScreen> createState() => _EngineerTasksScreenState();
}

class _EngineerTasksScreenState extends State<EngineerTasksScreen> {
  // Активное задание (заказ) инженера
  EngineerTask? _activeTask;
  
  // Список уведомлений для почтового ящика
  List<Notification> _notifications = [];
  
  // Список новых доступных заказов
  List<AvailableOrder> _availableOrders = [];
  
  // Подписка на обновления коллекции заказов
  StreamSubscription<QuerySnapshot>? _ordersSubscription;
  
  // Подписка на доступные заказы
  StreamSubscription<QuerySnapshot>? _availableOrdersSubscription;
  
  // Таймер для проверки существования активного заказа
  Timer? _checkActiveOrderTimer;
  
  // Загрузка заказов
  bool _isLoading = true;
  
  // Флаг наличия новых заказов
  bool _hasNewAvailableOrders = false;
  
  @override
  void initState() {
    super.initState();
    _loadTasksAndNotifications();
    _startAvailableOrdersMonitoring();
  }
  
  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _availableOrdersSubscription?.cancel();
    _checkActiveOrderTimer?.cancel();
    super.dispose();
  }
  
  // Метод для мониторинга доступных заказов
  void _startAvailableOrdersMonitoring() {
    final user = AuthService().currentUser;
    
    if (user == null) return;
    
    try {
      // Получаем данные инженера для проверки его специализации/региона
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .then((userDoc) {
            if (!userDoc.exists) return;
            
            final userData = userDoc.data() as Map<String, dynamic>?;
            if (userData == null) return;
            
            // Получаем специализацию и регион инженера для фильтрации заказов
            final List<String> specializations = userData['specializations'] is List 
                ? List<String>.from(userData['specializations'])
                : [];
                
            final String region = userData['region'] as String? ?? '';
            
            // Подписываемся на доступные заказы
            _availableOrdersSubscription = FirebaseFirestore.instance
                .collection('orders')
                .where('status', isEqualTo: 'новый')  // Заказы со статусом "новый"
                .where('assignedTo', isEqualTo: '')   // Не назначенные никому
                .snapshots()
                .listen((snapshot) {
                  List<AvailableOrder> availableOrders = [];
                  bool hasNewOrders = false;
                  
                  for (var doc in snapshot.docs) {
                    try {
                      final data = doc.data() as Map<String, dynamic>;
                      
                      // Проверяем соответствие заказа специализации и региону инженера
                      final String orderRegion = data['region'] as String? ?? '';
                      final String orderService = data['service'] as String? ?? '';
                      
                      // Условия подходящего заказа:
                      // 1. Регион совпадает (если указан)
                      // 2. Специализация инженера подходит (если указаны)
                      // 3. Заказ не назначен никому
                      bool isRegionMatch = region.isEmpty || orderRegion.isEmpty || region == orderRegion;
                      bool isSpecializationMatch = specializations.isEmpty || 
                                                  specializations.contains(orderService);
                      
                      if (isRegionMatch && isSpecializationMatch) {
                        // Проверяем, новый ли это заказ (создан менее 10 минут назад)
                        final Timestamp? createdAt = data['createdAt'] as Timestamp?;
                        bool isNew = false;
                        
                        if (createdAt != null) {
                          final DateTime createTime = createdAt.toDate();
                          final DateTime now = DateTime.now();
                          final difference = now.difference(createTime);
                          
                          isNew = difference.inMinutes < 10; // Считаем новым, если создан менее 10 минут назад
                          if (isNew) hasNewOrders = true;
                        }
                        
                        availableOrders.add(AvailableOrder(
                          id: doc.id,
                          title: data['title'] as String? ?? 'Заказ без названия',
                          address: data['address'] as String? ?? 'Адрес не указан',
                          clientName: data['clientName'] as String? ?? 'Клиент не указан',
                          price: (data['price'] is num) ? (data['price'] as num).toDouble() : 0.0,
                          service: orderService,
                          isNew: isNew,
                          createdAt: createdAt?.toDate(),
                        ));
                      }
                    } catch (e) {
                      print('Ошибка при обработке доступного заказа ${doc.id}: $e');
                    }
                  }
                  
                  if (mounted) {
                    setState(() {
                      _availableOrders = availableOrders;
                      
                      // Если появились новые заказы и их не было раньше, показываем уведомление
                      if (hasNewOrders && !_hasNewAvailableOrders) {
                        _showNewOrdersNotification();
                      }
                      
                      _hasNewAvailableOrders = hasNewOrders;
                    });
                  }
                },
                onError: (error) {
                  print('Ошибка при мониторинге доступных заказов: $error');
                });
          });
    } catch (e) {
      print('Ошибка при настройке мониторинга доступных заказов: $e');
    }
  }
  
  // Метод для показа уведомления о новых заказах
  void _showNewOrdersNotification() {
    if (!mounted) return;
    
    // Показываем уведомление только если у инженера нет активного заказа
    // или его статус - "назначен" (т.е. еще не принят в работу)
    if (_activeTask == null || _activeTask!.status == TaskStatus.pending) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Доступны новые заказы! Нажмите, чтобы посмотреть.'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Открыть',
            textColor: Colors.white,
            onPressed: () {
              _showAvailableOrdersDialog();
            },
          ),
        ),
      );
    }
  }
  
  // Метод для отображения диалога с доступными заказами
  void _showAvailableOrdersDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Заголовок
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Доступные заказы',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            
            // Список заказов
            Expanded(
              child: _availableOrders.isEmpty
                ? const Center(
                    child: Text(
                      'Нет доступных заказов',
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _availableOrders.length,
                    itemBuilder: (context, index) {
                      final order = _availableOrders[index];
                      return _buildAvailableOrderItem(order, ctx);
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Элемент списка доступных заказов
  Widget _buildAvailableOrderItem(AvailableOrder order, BuildContext dialogContext) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: order.isNew ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: order.isNew 
            ? Border.all(color: Colors.green, width: 1)
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Row(
          children: [
            Text(
              'Заказ #${order.id}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (order.isNew) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'НОВЫЙ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Услуга: ${order.service}',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              'Адрес: ${order.address}',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              'Клиент: ${order.clientName}',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${order.price.toStringAsFixed(2)} ₽',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                    fontSize: 16,
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    _requestOrder(order.id);
                    Navigator.pop(dialogContext);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Text('Запросить заказ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // Метод для запроса заказа
  Future<void> _requestOrder(String orderId) async {
    final user = AuthService().currentUser;
    
    if (user == null) return;
    
    try {
      // Получаем данные инженера
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (!userDoc.exists) return;
      
      final userData = userDoc.data() as Map<String, dynamic>?;
      if (userData == null) return;
      
      final String engineerName = userData['name'] as String? ?? 'Инженер';
      
      // Отправляем запрос на заказ
      await FirebaseFirestore.instance
          .collection('orderRequests')
          .add({
            'orderId': orderId,
            'engineerId': user.uid,
            'engineerName': engineerName,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Запрос на заказ отправлен'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('Ошибка при запросе заказа: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при запросе заказа: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Загрузка заказов и уведомлений
  Future<void> _loadTasksAndNotifications() async {
    setState(() {
      _isLoading = true;
    });
    
    final user = AuthService().currentUser;
    
    if (user == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    
    try {
      // Получаем UID инженера
      final String engineerId = user.uid;
      
      // Получаем имя пользователя для проверки поля assignedToName
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(engineerId)
          .get();
      
      String engineerName = "";
      if (userDoc.exists) {
        engineerName = userDoc.data()?['name'] ?? "";
      }
      
      print('=========== ДИАГНОСТИКА ЗАГРУЗКИ ЗАКАЗОВ ===========');
      print('Загрузка заказов для инженера с ID: $engineerId и именем: $engineerName');
      
      // Проверим конкретный документ, который видели на скриншоте
      try {
        final specificDoc = await FirebaseFirestore.instance
            .collection('orders')
            .doc('HPaSbDSsxJHRBaYXAHud')
            .get();
            
        if (specificDoc.exists) {
          final data = specificDoc.data()!;
          print('ПРОВЕРКА ДОКУМЕНТА HPaSbDSsxJHRBaYXAHud:');
          print('- assignedTo: "${data['assignedTo']}"');
          print('- assignedToName: "${data['assignedToName']}"');
          print('- status: "${data['status']}"');
          print('- этот заказ назначен текущему инженеру: ${data['assignedTo'] == engineerId || data['assignedToName'] == engineerName}');
        } else {
          print('Документ HPaSbDSsxJHRBaYXAHud не найден!');
        }
      } catch (e) {
        print('Ошибка при проверке конкретного документа: $e');
      }
      
      // Подписываемся на заказы, модифицируем запрос для обхода необходимости составных индексов
      _ordersSubscription = FirebaseFirestore.instance
          .collection('orders')
          .orderBy('lastUpdated', descending: true)
          .limit(50) // Ограничиваем количество для производительности
          .snapshots()
          .listen((snapshot) {
            EngineerTask? activeTask;
            List<Notification> notifications = [];
            
            // Фильтруем документы на стороне клиента с более гибкой проверкой
            final filteredDocs = snapshot.docs.where((doc) {
              final data = doc.data();
              
              // Проверяем, назначен ли заказ текущему инженеру по ID или имени - более гибкая проверка
              final String assignedTo = data['assignedTo'] ?? '';
              final String assignedToName = data['assignedToName'] ?? '';
              final String status = data['status'] ?? '';
              
              // Менее строгая проверка на соответствие
              final bool isAssignedToUser = 
                (assignedTo.isNotEmpty && (assignedTo.contains(engineerId) || engineerId.contains(assignedTo))) || 
                (assignedToName.isNotEmpty && (assignedToName.contains(engineerName) || engineerName.contains(assignedToName)));
              
              // Если это конкретный документ, который нас интересует, выполним специальную проверку
              if (doc.id == 'HPaSbDSsxJHRBaYXAHud') {
                print('Проверка документа HPaSbDSsxJHRBaYXAHud в подписке:');
                print('- assignedTo: "$assignedTo" (ожидается: "$engineerId")');
                print('- assignedToName: "$assignedToName" (ожидается: "$engineerName")');
                print('- status: "$status"');
                print('- соответствие: $isAssignedToUser');
              }
              
              return isAssignedToUser;
            }).toList();
            
            print('Всего заказов: ${snapshot.docs.length}, отфильтровано для инженера: ${filteredDocs.length}');
            
            for (var doc in filteredDocs) {
              try {
                final data = doc.data() as Map<String, dynamic>;
                
                // Выводим данные каждого заказа для отладки
                print('Заказ ${doc.id}: статус=${data['status']}, assignedTo=${data['assignedTo']}, assignedToName=${data['assignedToName']}');
                
                // Проверяем статус заказа
                String status = data['status'] ?? '';
                
                // Создаем уведомление из заказа
                final notification = _createNotificationFromOrder(doc.id, data);
                if (notification != null) {
                  notifications.add(notification);
                }
                
                // Если заказ в процессе/назначен, устанавливаем его как активный
                // Расширим список статусов для большей гибкости
                if (['назначен', 'принят', 'выехал', 'прибыл', 'работает', 'в процессе'].any((s) => status.toLowerCase().contains(s.toLowerCase()))) {
                  // Берем только первый активный заказ (можно изменить логику при необходимости)
                  if (activeTask == null) {
                    activeTask = _convertToEngineerTask(doc.id, data);
                  }
                }
              } catch (e) {
                print('Ошибка при обработке заказа ${doc.id}: $e');
              }
            }
            
            // Проверяем, не был ли текущий активный заказ удален
            if (_activeTask != null) {
              bool activeTaskExists = false;
              for (var doc in filteredDocs) {
                if (doc.id == _activeTask!.id) {
                  activeTaskExists = true;
                  break;
                }
              }
              
              // Если активный заказ больше не существует в Firestore
              if (!activeTaskExists) {
                print('Активный заказ ${_activeTask!.id} больше не существует в базе данных');
                // Создаем уведомление о том, что заказ был удален
                final deleteNotification = Notification(
                  id: 'deleted_${_activeTask!.id}',
                  title: 'Заказ №${_activeTask!.id} удален',
                  message: 'Заказ был удален диспетчером или администратором.',
                  time: DateTime.now().toString(),
      isRead: false,
                );
                notifications.add(deleteNotification);
                
                // Показываем уведомление
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Заказ №${_activeTask!.id} был удален из системы'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            }
            
            if (mounted) {
              setState(() {
                _activeTask = activeTask;
                _notifications = notifications;
                _isLoading = false;
              });
              
              // Если есть новые непрочитанные уведомления, показываем всплывающее уведомление
              final newNotifications = notifications.where((n) => !n.isRead).toList();
              if (newNotifications.isNotEmpty) {
                _showNewAssignedTaskNotification(newNotifications.length);
              }
            }
          },
          onError: (error) {
            print('Ошибка при загрузке заказов инженера: $error');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          });
      
      // Добавляем функцию для проверки существования активного заказа каждые 30 секунд
      _checkActiveOrderTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
        if (_activeTask != null) {
          try {
            // Проверяем, существует ли заказ в Firestore
            final orderDoc = await FirebaseFirestore.instance
                .collection('orders')
                .doc(_activeTask!.id)
                .get();
            
            if (!orderDoc.exists && mounted) {
              print('Заказ ${_activeTask!.id} не найден при периодической проверке');
              setState(() {
                _activeTask = null;
              });
              
              // Показываем уведомление пользователю
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Заказ был удален из системы'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            }
          } catch (e) {
            print('Ошибка при проверке существования заказа: $e');
          }
        }
      });
    } catch (e) {
      print('Ошибка при настройке слушателя заказов инженера: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Метод для отображения уведомления о новых назначенных заказах
  void _showNewAssignedTaskNotification(int count) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Вам назначено $count ${count == 1 ? 'новый заказ' : 'новых заказа(ов)'}'),
        backgroundColor: const Color(0xFFD04E4E),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Открыть',
          textColor: Colors.white,
          onPressed: () {
            _openMailbox(context);
          },
        ),
      ),
    );
  }
  
  // Конвертация данных заказа в уведомление
  Notification? _createNotificationFromOrder(String orderId, Map<String, dynamic> data) {
    try {
      // Получаем основную информацию о заказе
      final String title = data['title'] ?? 'Заказ без названия';
      final String status = data['status'] ?? '';
      final Timestamp? updatedAt = data['updatedAt'] as Timestamp?;
      final String address = data['address'] ?? 'Адрес не указан';
      
      // Формируем сообщение в зависимости от статуса
      String message;
      bool isRead = data['notificationRead'] ?? false;
      
      switch (status) {
        case 'назначен':
          message = 'Вам назначен новый заказ: $title. Адрес: $address';
          break;
        case 'в процессе':
          message = 'Заказ в процессе выполнения: $title';
          break;
        case 'выполнен':
          message = 'Заказ успешно выполнен: $title';
          isRead = true; // Автоматически отмечаем как прочитанное
          break;
        case 'отменен':
          message = 'Заказ был отменен: $title';
          isRead = true; // Автоматически отмечаем как прочитанное
          break;
        default:
          message = 'Статус заказа изменен на: $status';
      }
      
      // Форматируем дату
      String time;
      if (updatedAt != null) {
        final date = updatedAt.toDate();
        time = '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      } else {
        time = 'Нет данных о времени';
      }
      
      return Notification(
        id: orderId,
        title: 'Заказ №$orderId',
        message: message,
        time: time,
        isRead: isRead,
      );
    } catch (e) {
      print('Ошибка при создании уведомления из заказа: $e');
      return null;
    }
  }
  
  // Конвертация данных заказа в задание инженера
  EngineerTask _convertToEngineerTask(String orderId, Map<String, dynamic> data) {
    // Отладочный вывод данных заказа
    print('Конвертация заказа $orderId: ${data.toString()}');
    
    // Проверяем, кому назначен заказ (по ID или по имени)
    final user = AuthService().currentUser;
    final bool assignedByName = data['assignedToName'] != null && 
                               (data['assignedTo'] == null || data['assignedTo'].isEmpty);
    
    if (assignedByName) {
      print('Заказ назначен по имени: ${data['assignedToName']}');
    } else {
      print('Заказ назначен по ID: ${data['assignedTo']}');
    }
    
    // Обработка имени клиента с дополнительной проверкой
    String clientName = data['displayName'] ?? '';
    
    // Если displayName пустой, проверяем userName
    if (clientName.isEmpty && data['userName'] != null) {
      clientName = data['userName'];
    }
    
    // Если всё еще пустой, используем имя из clientName
    if (clientName.isEmpty && data['clientName'] != null) {
      clientName = data['clientName'];
    }
    
    // Если всё еще пустой, показываем заглушку
    if (clientName.isEmpty) {
      clientName = 'Имя клиента не указано';
    }
    
    // Извлечение additionalInfo вместо description
    String description = data['additionalInfo'] ?? '';
    if (description.isEmpty && data['description'] != null) {
      description = data['description'];
    }
    
    // Статус задания
    TaskStatus taskStatus;
    switch (data['status']) {
      case 'назначен':
        taskStatus = TaskStatus.pending;
        break;
      case 'принят':
        taskStatus = TaskStatus.accepted;
        break;
      case 'выехал':
        taskStatus = TaskStatus.onWay;
        break;
      case 'прибыл':
        taskStatus = TaskStatus.arrived;
        break;
      case 'работает':
        taskStatus = TaskStatus.working;
        break;
      case 'в процессе':
        taskStatus = TaskStatus.inProgress;
        break;
      case 'выполнен':
        taskStatus = TaskStatus.completed;
        break;
      default:
        print('Неизвестный статус: ${data['status']}');
        taskStatus = TaskStatus.pending;
    }
    
    // Действие в зависимости от статуса
    String currentAction;
    switch (data['status']) {
      case 'назначен':
        currentAction = 'Принять заказ';
        break;
      case 'принят':
        currentAction = 'Выехать на заказ';
        break;
      case 'выехал':
        currentAction = 'Прибыл на объект';
        break;
      case 'прибыл':
        currentAction = 'Начать работу';
        break;
      case 'работает':
        currentAction = 'Завершить работу';
        break;
      case 'в процессе':
        currentAction = 'Завершить заказ';
        break;
      default:
        currentAction = 'Связаться с диспетчером';
    }
    
    // Временная шкала (история статусов)
    Map<String, String> timeline = {};
    
    // Проверяем есть ли статус "назначен" в истории
    if (data['statusEvents'] == null || !(data['statusEvents'] is List) || (data['statusEvents'] as List).isEmpty) {
      // Если истории нет или она пуста, добавляем начальный статус "Назначен"
      // Получаем дату создания заказа или текущую дату
      final DateTime createdAt = data['createdAt'] is Timestamp 
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now();
      
      // Форматируем дату
      final String formattedDateTime = "${createdAt.day.toString().padLeft(2, '0')}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}:${createdAt.second.toString().padLeft(2, '0')}";
      
      // Добавляем статус "Назначен" в таймлайн
      timeline['Назначен'] = formattedDateTime;
      print('Добавлен статус в таймлайн: Назначен -> $formattedDateTime');
    }
    
    // Добавляем все остальные статусы из истории
    if (data['statusEvents'] != null && data['statusEvents'] is List) {
      print('StatusEvents: ${data['statusEvents']}');
      for (var event in data['statusEvents']) {
        if (event is Map<String, dynamic> && 
            event['status'] != null && 
            event['dateTime'] != null) {
          timeline[event['status']] = event['dateTime'];
          print('Добавлен статус в таймлайн: ${event['status']} -> ${event['dateTime']}');
        }
      }
    }
    
    return EngineerTask(
      id: orderId,
      address: data['address'] ?? 'Адрес не указан',
      status: taskStatus,
      clientName: clientName,
      phone: data['userPhone'] ?? data['clientPhone'] ?? 'Телефон не указан',
      description: description,
      cost: (data['price'] is num) ? (data['price'] as num).toDouble() : 0.0,
      timeline: timeline,
      currentAction: currentAction,
      clientId: data['clientId'] ?? data['userId'],
    );
  }
  
  // Отметка уведомления как прочитанное и обновление в Firestore
  Future<void> _markNotificationAsRead(Notification notification) async {
    try {
      // Отмечаем локально
      setState(() {
        notification.isRead = true;
      });
      
      // Обновляем статус в Firestore
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(notification.id)
          .update({
            'notificationRead': true,
          });
    } catch (e) {
      print('Ошибка при отметке уведомления как прочитанное: $e');
    }
  }
  
  // Открытие модального окна с почтовым ящиком
  void _openMailbox(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Заголовок
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Назначенные заказы',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            
            // Список уведомлений
            Expanded(
              child: _isLoading 
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFFD04E4E),
                    ),
                  )
                : _notifications.isEmpty
                ? const Center(
                    child: Text(
                      'Нет новых уведомлений',
                      style: TextStyle(
                        color: Colors.grey,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notification = _notifications[index];
                      return _buildNotificationItem(notification);
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Элемент списка уведомлений
  Widget _buildNotificationItem(Notification notification) {
    // Проверяем, является ли это уведомление текущим активным заказом
    final bool isActive = _activeTask != null && _activeTask!.id == notification.id;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive 
            ? const Color(0xFFD04E4E).withOpacity(0.1)
            : notification.isRead 
                ? Colors.grey[100] 
                : Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: isActive 
            ? Border.all(color: const Color(0xFFD04E4E), width: 2)
            : null,
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isActive 
                ? const Color(0xFFD04E4E)
                : notification.isRead 
                    ? Colors.grey[300] 
                    : const Color(0xFFD04E4E),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isActive 
                ? Icons.check_circle
                : Icons.notifications,
            color: isActive || !notification.isRead 
                ? Colors.white 
                : Colors.grey[600],
          ),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              notification.message,
              style: const TextStyle(
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              notification.time,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: () {
          // Если заказ не активен и не прочитан, отмечаем его как прочитанный
          if (!isActive && !notification.isRead) {
            _markNotificationAsRead(notification);
          }
          
          // Устанавливаем активный заказ
          _setActiveTask(notification.id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // Убираем floatingActionButton и floatingActionButtonLocation
      body: Stack(
        children: [
          // Основной контент
          _isLoading 
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFD04E4E),
                  ),
                )
              : _activeTask == null 
          ? _buildEmptyTasksView()
          : SingleChildScrollView(
              child: _buildTaskCard(_activeTask!),
            ),
              
          // Добавляем кнопку почтового ящика в правый верхний угол
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(30),
              color: Colors.white,
              child: InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: () => _openMailbox(context),
                child: Stack(
                  clipBehavior: Clip.none,
        children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        Icons.mail_outline, 
                        color: Color(0xFFD04E4E),
                        size: 28,
                      ),
                    ),
                    
                    // Индикатор новых уведомлений
                    if (_hasNewAvailableOrders)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: const Center(
                            child: Text(
                              'Н',
            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
    );
  }
  
  // Новый стиль карточки задания инженера
  Widget _buildTaskCard(EngineerTask task) {
    final bool isCompleted = task.status == TaskStatus.completed;
    final bool isPending = task.status == TaskStatus.pending;
    
    return Column(
      children: [
        // Карточка с основной информацией
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Номер заказа и статус
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                'Заказ №${task.id}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                      overflow: TextOverflow.visible,
                      softWrap: true,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isPending 
                          ? Colors.orange.withOpacity(0.2) 
                          : Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isPending ? 'Назначен' : 'В работе',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isPending ? Colors.orange : Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
        
        // Адрес
              const Text(
                'Адрес:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                width: double.infinity,
          child: Text(
            task.address,
            style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.visible,
                  softWrap: true,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Данные клиента
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
        // Имя клиента
                  const Text(
                    'Клиент:',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
          child: Text(
            task.clientName,
            style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
            ),
                      overflow: TextOverflow.visible,
                      softWrap: true,
          ),
        ),
                  const SizedBox(height: 10),
        
        // Телефон
                  if (task.phone != 'Телефон не указан')
                    GestureDetector(
                      onTap: () {
                        // Логика для звонка
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD04E4E).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.phone, color: Color(0xFFD04E4E), size: 18),
                            const SizedBox(width: 6),
                            Flexible(
          child: Text(
            task.phone,
            style: const TextStyle(
                                  color: Color(0xFFD04E4E),
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.visible,
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.phone_disabled, color: Colors.grey, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Телефон не указан',
                            style: TextStyle(
              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        
        // Карточка с описанием
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Описание задания
              const Text(
                'Дополнительная информация:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                width: double.infinity,
          child: Text(
            task.description,
            style: const TextStyle(
                    fontSize: 15,
            ),
                  overflow: TextOverflow.visible,
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
        
        // Карточка со стоимостью и кнопкой действия
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Стоимость
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                    'Стоимость:',
                style: TextStyle(
                  fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD04E4E).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${task.cost.toStringAsFixed(2)} ₽',
                style: const TextStyle(
                        fontSize: 18,
                  fontWeight: FontWeight.bold,
                        color: Color(0xFFD04E4E),
                      ),
                ),
              ),
            ],
              ),
              
              const SizedBox(height: 24),
          
        // Кнопка действия
              SizedBox(
            width: double.infinity,
                height: 52,
            child: ElevatedButton(
              onPressed: () {
                    // Выбираем действие в зависимости от статуса заказа
                    switch (task.status) {
                      case TaskStatus.pending:
                        _acceptOrder();
                        break;
                      case TaskStatus.accepted:
                        _startTrip();
                        break;
                      case TaskStatus.onWay:
                        _arriveAtLocation();
                        break;
                      case TaskStatus.arrived:
                        _startWork();
                        break;
                      case TaskStatus.working:
                      case TaskStatus.inProgress:
                        _completeWork();
                        break;
                      case TaskStatus.completed:
                      case TaskStatus.rejected:
                        // Кнопка неактивна для завершенных или отклоненных заказов
                        break;
                    }
                  },
                  // Кнопка неактивна только для завершенных или отклоненных заказов
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD04E4E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                ),
                    elevation: 2,
                    disabledBackgroundColor: Colors.grey[300],
                    disabledForegroundColor: Colors.grey[600],
              ),
              child: Text(
                task.currentAction,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        
              // Ссылка на отмену заказа, если он еще не выполнен и не в процессе выполнения
              if (task.status == TaskStatus.pending || task.status == TaskStatus.accepted)
          Padding(
                  padding: const EdgeInsets.only(top: 12),
            child: Center(

            ),
          ),
            ],
          ),
        ),
        
        // Отображаем таймлайн статусов, если есть активности
        if (task.timeline.isNotEmpty)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'История статусов',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _buildStatusTimeline(task),
              ],
            ),
          ),
        
        // Дополнительный отступ внизу
        const SizedBox(height: 80),
      ],
    );
  }
  
  // Элемент таймлайна
  Widget _buildTimelineItem(String action, String time) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Маркер таймлайна
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFD04E4E),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              Container(
                width: 2,
                height: 20,
                color: const Color(0xFFD04E4E),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  time,
                  style: const TextStyle(
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Метод для установки активного заказа
  void _setActiveTask(String orderId) {
    if (_isLoading) return;
    
    // Проверяем, есть ли уже активный заказ и его статус
    if (_activeTask != null && 
        _activeTask!.status != TaskStatus.pending && 
        _activeTask!.status != TaskStatus.completed) {
      // Если заказ в работе, не позволяем выбрать другой
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('У вас уже есть активный заказ в работе. Завершите его перед тем, как взять новый.'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context);
      return;
    }
    
    // Находим заказ среди уведомлений по его ID
    for (var notification in _notifications) {
      if (notification.id == orderId) {
        // Получаем данные заказа из Firestore
        FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .get()
            .then((doc) {
              if (doc.exists) {
                final data = doc.data() as Map<String, dynamic>;
                final String status = data['status'] ?? '';
                
                // Проверяем, можно ли выбрать этот заказ (только заказы со статусом "назначен")
                if (status == 'назначен') {
                  setState(() {
                    _activeTask = _convertToEngineerTask(orderId, data);
                  });
                } else {
                  // Показываем сообщение, что заказ уже принят и не может быть изменен
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        status == 'в процессе' 
                            ? 'Этот заказ уже принят и не может быть изменен'
                            : 'Этот заказ нельзя выбрать (статус: $status)'
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            });
        break;
      }
    }
    
    // Закрываем почтовый ящик
    Navigator.pop(context);
  }
  
  // Принятие заказа (изменение статуса с "назначен" на "принят")
  Future<void> _acceptOrder() async {
    await _updateOrderStatus('принят', 'Принят в работу', 'Заказ принят исполнителем');
  }

  // Выезд на заказ
  Future<void> _startTrip() async {
    if (_activeTask == null) return;
    
    try {
      // Получаем текущий документ заказа для проверки статуса
      final orderRef = FirebaseFirestore.instance.collection('orders').doc(_activeTask!.id);
      final orderDoc = await orderRef.get();
      
      if (!orderDoc.exists) {
        throw Exception('Заказ не найден');
      }
      
      final data = orderDoc.data() as Map<String, dynamic>;
      final String status = data['status'] ?? '';
      
      // Проверяем, что заказ в статусе "принят"
      if (status != 'принят') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Статус заказа изменился. Обновите данные.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      
      // Вызываем общий метод обновления статуса
      await _updateOrderStatus('выехал', 'Выехал на заказ', 'Инженер выехал на заказ');
    } catch (e) {
      print('Ошибка при выезде на заказ: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при выезде на заказ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Метод для проверки кода подтверждения
  Future<bool> _checkConfirmationCode(String orderId, String enteredCode, String codeType) async {
    try {
      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .get();
      
      if (!orderDoc.exists) {
        return false;
      }
      
      final orderData = orderDoc.data() as Map<String, dynamic>;
      final correctCode = codeType == 'arrival' 
          ? orderData['arrivalCode'] as String?
          : orderData['completionCode'] as String?;
      
      return correctCode != null && correctCode == enteredCode;
    } catch (e) {
      print('Ошибка при проверке кода подтверждения: $e');
      return false;
    }
  }

  // Диалог для ввода кода подтверждения
  Future<bool> _showConfirmationCodeDialog(String codeType) async {
    final codeController = TextEditingController();
    bool isLoading = false;
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(
                codeType == 'arrival' 
                    ? 'Подтверждение прибытия'
                    : 'Подтверждение завершения работы',
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: const Color(0xFF2D2D2D),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    codeType == 'arrival'
                        ? 'Введите код подтверждения прибытия:'
                        : 'Введите код подтверждения завершения работы:',
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(
                      hintText: 'Введите 4-значный код',
                      counterText: '',
                      border: OutlineInputBorder(),
                      hintStyle: TextStyle(color: Colors.grey),
                    ),
                    style: const TextStyle(
                      fontSize: 24,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(
                      color: Color(0xFFD04E4E),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () {
                    Navigator.of(context).pop(false);
                  },
                  child: const Text('Отмена', style: TextStyle(color: Colors.white)),
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
                    
                    final isCorrect = await _checkConfirmationCode(
                      _activeTask!.id,
                      codeController.text,
                      codeType,
                    );
                    
                    setState(() {
                      isLoading = false;
                    });
                    
                    if (isCorrect) {
                      Navigator.of(context).pop(true);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Неверный код подтверждения'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD04E4E),
                    foregroundColor: Colors.white,
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

  // Обновляем метод _arriveAtLocation для использования кода подтверждения прибытия
  Future<void> _arriveAtLocation() async {
    if (_activeTask == null) return;
    
    final confirmed = await _showConfirmationCodeDialog('arrival');
    if (!confirmed) return;
    
    await _updateOrderStatus(
      'прибыл',
      'Прибыл на объект',
      'Инженер прибыл на объект',
    );
  }

  // Начало работы
  Future<void> _startWork() async {
    await _updateOrderStatus('работает', 'Начал работу', 'Инженер приступил к работе');
  }

  // Завершение работы (требуется подтверждение клиента)
  Future<void> _completeWork() async {
    try {
      if (_activeTask == null) {
        print('_completeWork: _activeTask = null, выход из метода');
        return;
      }
      
      // Сохраняем ID заказа до вызова методов, которые могут изменить _activeTask
      final String orderId = _activeTask!.id;
      if (orderId.isEmpty) {
        print('_completeWork: ID заказа пуст, выход из метода');
        return;
      }
      
      print('Запускаем процесс завершения работы для заказа: $orderId');
      
      final confirmed = await _showConfirmationCodeDialog('completion');
      if (!confirmed) {
        print('_completeWork: подтверждение не получено, выход из метода');
        return;
      }
      
      // Обновляем статус заказа
      await _updateOrderStatus(
        'выполнен',
        'Завершил работу',
        'Инженер завершил работу',
      );
      
      print('Статус заказа $orderId изменен на "выполнен", перемещаем заказ в историю');
      
      // После успешного завершения работы, перемещаем заказ в историю
      // Передаем сохраненный ID вместо обращения к _activeTask
      await _moveOrderToHistory(orderId);
    } catch (e) {
      print('Ошибка в методе _completeWork: $e');
      print(StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при завершении работы: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Метод для перемещения заказа в историю
  Future<void> _moveOrderToHistory(String orderId) async {
    try {
      print('Запуск _moveOrderToHistory для заказа: $orderId');
      
      // Получаем документ заказа
      final orderDoc = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .get();
      
      if (!orderDoc.exists) {
        print('Ошибка: заказ $orderId не найден при попытке переместить его в историю');
        return;
      }
      
      // Получаем текущего пользователя
      final user = AuthService().currentUser;
      if (user == null) {
        print('Ошибка: пользователь не авторизован при попытке переместить заказ $orderId в историю');
        return;
      }
      
      // Получаем данные пользователя из Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      String userName = '';
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>?;
        userName = userData?['name'] ?? '';
      }
      
      // Получаем данные заказа (безопасно - проверяем на null)
      final orderData = orderDoc.data();
      if (orderData == null) {
        print('Ошибка: данные заказа $orderId пусты');
        return;
      }
      
      print('===== ПЕРЕМЕЩЕНИЕ ЗАКАЗА В ИСТОРИЮ =====');
      print('Заказ ID: $orderId');
      print('Текущий пользователь: ID=${user.uid}, DisplayName=$userName');
      
      // Получаем информацию о клиенте (безопасно)
      final String clientId = orderData['userId'] as String? ?? '';
      final String clientName = orderData['userName'] as String? ?? 
                               orderData['clientName'] as String? ?? 'Клиент не указан';
      
      print('Клиент ID: $clientId, Имя: $clientName');
      print('Проверка ID клиента перед созданием записи истории: "${clientId}" (пустой: ${clientId.isEmpty})');
      
      // Создаем данные для записи в историю
      final Map<String, dynamic> historyData = {
        'completedAt': FieldValue.serverTimestamp(),
        'originalOrderId': orderId,
        'assignedTo': user.uid,
        'assignedToName': userName,
        'status': 'выполнен',
      };
      
      // Добавляем безопасно все остальные поля из оригинального заказа
      orderData.forEach((key, value) {
        if (value != null) {
          historyData[key] = value;
        }
      });
      
      // Добавляем дополнительные поля, если они существуют
      historyData['arrivalCode'] = orderData['arrivalCode'] as String? ?? 'Не указан';
      historyData['completionCode'] = orderData['completionCode'] as String? ?? 'Не указан';
      
      // Сохраняем userId явно для гарантии сохранения ID клиента
      if (clientId.isNotEmpty) {
        historyData['userId'] = clientId;
      }
      
      // Создаем запись в истории
      final historyRef = await FirebaseFirestore.instance.collection('order_history').add(historyData);
      
      print('Заказ успешно сохранен в историю с ID: ${historyRef.id}');
      
      // Удаляем заказ из основной коллекции
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .delete();
      
      print('Заказ $orderId успешно удален из основной коллекции');
      
      // Показываем модальное окно для оценки клиента
      // Проверяем наличие ID клиента
      if (clientId.isNotEmpty) {
        print('ID клиента не пустой, можно показать диалог оценки');
        if (mounted) {
          print('Компонент смонтирован, показываем диалог после задержки');
          
          // Используем более длинную задержку, чтобы дать больше времени на закрытие предыдущих диалогов
          await Future.delayed(const Duration(seconds: 1));
          
          if (mounted) {
            print('Вызываем _showClientRatingDialog для клиента: $clientName');
            // Непосредственно показываем диалог, без использования Future.delayed
            _showClientRatingDialog(orderId, clientId, clientName, historyRef.id);
          } else {
            print('Компонент размонтирован после задержки, диалог не будет показан');
          }
        } else {
          print('Компонент не смонтирован, диалог не будет показан');
        }
      } else {
        print('Отзыв не будет показан, так как ID клиента пустой');
      }
    } catch (e) {
      print('Ошибка при перемещении заказа в историю: $e');
      // Выводим стек ошибки для отладки
      print(StackTrace.current);
    }
  }

  // Метод для отображения модального окна оценки клиента
  void _showClientRatingDialog(String orderId, String clientId, String clientName, String historyId) {
    try {
      // Проверяем, что все параметры не пустые
      if (orderId.isEmpty || clientId.isEmpty || historyId.isEmpty) {
        print('Ошибка: один из параметров пустой: orderId=$orderId, clientId=$clientId, historyId=$historyId');
        return;
      }
      
      print('Показываем диалог оценки для клиента: $clientName (ID: $clientId)');
      print('Вызов showDialog для отображения окна с оценкой');
      
      // Оценка по умолчанию
      double rating = 5.0;
      // Текст комментария
      String comment = '';
      
      if (!mounted) {
        print('Компонент не монтирован, диалог не будет показан');
        return;
      }
      
      // Делаем принудительное обновление состояния, чтобы гарантировать корректный контекст
      setState(() {});
      
      // Показываем диалог с небольшой задержкой для гарантии правильного контекста
      Future.microtask(() {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: Text('Оценка клиента'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Как вам работалось с клиентом $clientName?'),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${rating.toInt()}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Icon(Icons.star, color: Colors.amber, size: 30),
                        ],
                      ),
                      Slider(
                        value: rating,
                        min: 1.0,
                        max: 5.0,
                        divisions: 4,
                        label: rating.toInt().toString(),
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
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.grey[100],
                        ),
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
                    child: Text('Пропустить'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      _saveClientReview(orderId, clientId, clientName, rating.toInt(), comment, historyId);
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD04E4E),
                    ),
                    child: Text('Отправить', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ).catchError((error) {
            print('Ошибка при отображении диалога: $error');
            print(StackTrace.current);
          });
        } else {
          print('Компонент размонтирован в Future.microtask, диалог не будет показан');
        }
      });
    } catch (e) {
      print('Ошибка при отображении диалога оценки клиента: $e');
      print(StackTrace.current);
    }
  }
  
  // Метод для сохранения отзыва о клиенте в Firestore
  Future<void> _saveClientReview(
    String orderId, 
    String clientId, 
    String clientName, 
    int rating, 
    String comment,
    String historyId
  ) async {
    try {
      print('Сохраняем отзыв: orderId=$orderId, clientId=$clientId, rating=$rating');
      
      // Безопасно проверяем все значения
      if (orderId.isEmpty || clientId.isEmpty || historyId.isEmpty) {
        print('Ошибка: невозможно сохранить отзыв с пустыми значениями');
        return;
      }
      
      final user = AuthService().currentUser;
      if (user == null) {
        print('Ошибка: пользователь не авторизован при попытке сохранить отзыв');
        return;
      }
      
      // Получаем данные пользователя
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      String userName = '';
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>?;
        if (userData != null) {
          userName = userData['name'] as String? ?? '';
        }
      }
      
      // Сохраняем отзыв в новой коллекции reviews
      final reviewRef = await FirebaseFirestore.instance.collection('reviews').add({
        'orderId': orderId,
        'historyId': historyId,
        'clientId': clientId,
        'clientName': clientName,
        'engineerId': user.uid,
        'engineerName': userName,
        'rating': rating,
        'comment': comment,
        'type': 'engineer_to_client', // Тип отзыва: от инженера клиенту
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      print('Отзыв о клиенте успешно сохранен с ID: ${reviewRef.id}');
      
      // Обновляем средний рейтинг клиента
      await _updateClientAverageRating(clientId);
      
      // Показываем уведомление об успешной отправке отзыва
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ваш отзыв успешно отправлен!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Ошибка при сохранении отзыва о клиенте: $e');
      print(StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при отправке отзыва'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // Метод для обновления среднего рейтинга клиента
  Future<void> _updateClientAverageRating(String clientId) async {
    try {
      if (clientId.isEmpty) {
        print('Ошибка: ID клиента пустой, невозможно обновить рейтинг');
        return;
      }
      
      print('Обновляем средний рейтинг для клиента: $clientId');
      
      // Получаем все отзывы для данного клиента
      final reviewsSnapshot = await FirebaseFirestore.instance
          .collection('reviews')
          .where('clientId', isEqualTo: clientId)
          .where('type', isEqualTo: 'engineer_to_client')
          .get();
      
      if (reviewsSnapshot.docs.isEmpty) {
        print('Нет отзывов для клиента $clientId');
        return;
      }
      
      // Вычисляем средний рейтинг
      double totalRating = 0;
      int count = 0;
      
      for (final doc in reviewsSnapshot.docs) {
        final data = doc.data();
        if (data == null) continue;
        
        final rating = data['rating'] as int?;
        if (rating != null) {
          totalRating += rating;
          count++;
        }
      }
      
      if (count > 0) {
        final averageRating = totalRating / count;
        
        // Обновляем средний рейтинг клиента в его документе
        await FirebaseFirestore.instance
            .collection('users')
            .doc(clientId)
            .update({
              'rating': averageRating,
              'ratingCount': count,
            });
        
        print('Средний рейтинг клиента обновлен: $averageRating ($count отзывов)');
      }
    } catch (e) {
      print('Ошибка при обновлении среднего рейтинга клиента: $e');
      print(StackTrace.current);
    }
  }

  // Новый метод для обновления статуса заказа
  Future<void> _updateOrderStatus(String newStatus, String statusText, String notes, {bool needConfirmation = false}) async {
    try {
      // Сохраняем ссылку на текущую задачу локально
      final EngineerTask? currentTask = _activeTask;
      
      if (currentTask == null) {
        print('_updateOrderStatus: _activeTask = null, выход из метода');
        return;
      }
      
      // Сохраняем все необходимые данные в локальных переменных
      final String orderId = currentTask.id;
      final String address = currentTask.address ?? '';
      final String clientName = currentTask.clientName ?? '';
      final String phone = currentTask.phone ?? '';
      final String description = currentTask.description ?? '';
      final double cost = currentTask.cost ?? 0.0;
      final String? clientId = currentTask.clientId;
      final Map<String, String> existingTimeline = Map<String, String>.from(currentTask.timeline ?? {});
      
      if (orderId.isEmpty) {
        print('_updateOrderStatus: orderId пустой, выход из метода');
        return;
      }
      
      // Дополнительная отладочная информация
      print('Попытка обновления статуса: с ${currentTask.status} на $newStatus (statusText: $statusText)');
      print('ID заказа: $orderId, клиент: $clientName, clientId: $clientId');
      
      // Если требуется подтверждение клиента, показываем модальное окно
      if (needConfirmation) {
        final confirmed = await _showClientConfirmationDialog(statusText);
        if (!confirmed) return; // Если пользователь отменил, прерываем выполнение
      }
      
      // Получаем текущий документ заказа
      final orderRef = FirebaseFirestore.instance.collection('orders').doc(orderId);
      final orderDoc = await orderRef.get();
      
      if (!orderDoc.exists) {
        print('_updateOrderStatus: Документ заказа не существует');
        throw Exception('Заказ не найден');
      }
      
      final data = orderDoc.data();
      if (data == null) {
        print('_updateOrderStatus: Данные заказа = null');
        throw Exception('Данные заказа отсутствуют');
      }
      
      // Отладочная информация текущего заказа
      print('Данные заказа: ${data.toString()}');
      
      // Проверяем текущий статус заказа для корректного перехода между статусами
      final currentStatus = data['status'] as String? ?? '';
      final bool isValidTransition = _isValidStatusTransition(currentStatus, newStatus);
      
      print('Текущий статус в БД: $currentStatus, переход возможен: $isValidTransition');
      
      if (!isValidTransition) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Невозможно изменить статус с "$currentStatus" на "$newStatus"'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      // Получаем текущие события статуса
      List<dynamic> currentEvents = [];
      if (data['statusEvents'] != null) {
        currentEvents = List<dynamic>.from(data['statusEvents']);
      }
      
      // Форматируем текущее время для отображения
      final DateTime now = DateTime.now();
      final String formattedDateTime = "${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      
      // Добавляем новое событие
      final updatedEvents = [
        ...currentEvents,
        {
          'status': statusText,
          'dateTime': formattedDateTime,
          'notes': notes,
        }
      ];
      
      // Подготавливаем данные для обновления
      Map<String, dynamic> updateData = {
        'status': newStatus,
        'statusEvents': updatedEvents,
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      
      // Если статус 'принят', 'выехал', 'работает', получаем и сохраняем геолокацию инженера
      if (newStatus == 'принят' || newStatus == 'выехал' || newStatus == 'работает' || newStatus == 'прибыл') {
        print('Получаем геолокацию инженера для статуса: $newStatus');
        final locationData = await _getCurrentLocation();
        
        if (locationData != null) {
          // Обновляем данные с геолокацией
          if (newStatus == 'принят') {
            updateData['engineerLocationAtAccept'] = locationData;
            print('Добавлена геолокация инженера при принятии заказа: $locationData');
          } else if (newStatus == 'выехал') {
            updateData['engineerLocationAtDeparture'] = locationData;
            print('Добавлена геолокация инженера при выезде на заказ: $locationData');
          } else if (newStatus == 'работает') {
            updateData['engineerLocationAtWork'] = locationData;
            print('Добавлена геолокация инженера при начале работы: $locationData');
          } else if (newStatus == 'прибыл') {
            updateData['engineerLocationAtArrival'] = locationData;
            print('Добавлена геолокация инженера при прибытии на объект: $locationData');
          }
        } else {
          print('Не удалось получить геолокацию инженера');
        }
      }
      
      // Если статус 'принят', 'выехал', 'прибыл' или 'работает', получаем и сохраняем геолокацию инженера
      if (newStatus == 'принят' || newStatus == 'выехал' || newStatus == 'работает' || newStatus == 'прибыл') {
        print('[ЗАКАЗ-ГЕО] Запрос на сохранение геолокации для статуса: $newStatus, ID заказа: $orderId');
        print('[ЗАКАЗ-ГЕО] Вызываем _getCurrentLocation()');
        final locationData = await _getCurrentLocation();
        
        if (locationData != null) {
          print('[ЗАКАЗ-ГЕО] Геолокация получена успешно');
          // Обновляем данные с геолокацией
          if (newStatus == 'принят') {
            updateData['engineerLocationAtAccept'] = locationData;
            print('[ЗАКАЗ-ГЕО] Добавлена геолокация инженера при принятии заказа: $locationData');
          } else if (newStatus == 'выехал') {
            updateData['engineerLocationAtDeparture'] = locationData;
            print('[ЗАКАЗ-ГЕО] Добавлена геолокация инженера при выезде на заказ: $locationData');
          } else if (newStatus == 'прибыл') {
            updateData['engineerLocationAtArrival'] = locationData;
            print('[ЗАКАЗ-ГЕО] Добавлена геолокация инженера при прибытии на объект: $locationData');
          } else if (newStatus == 'работает') {
            updateData['engineerLocationAtWork'] = locationData;
            print('[ЗАКАЗ-ГЕО] Добавлена геолокация инженера при начале работы: $locationData');
          }
        } else {
          print('[ЗАКАЗ-ГЕО] НЕ УДАЛОСЬ получить геолокацию');
          print('[ЗАКАЗ-ГЕО] Используем временные тестовые данные для отладки');
          
          // Тестовые данные для отладки (координаты центра Нижнего Новгорода)
          final testLocationData = {
            'latitude': 56.3269,
            'longitude': 44.0059,
            'accuracy': 10.0,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'isTest': true, // Метка, что это тестовые данные
          };
          
          if (newStatus == 'принят') {
            updateData['engineerLocationAtAccept'] = testLocationData;
            print('[ЗАКАЗ-ГЕО] Добавлены ТЕСТОВЫЕ данные геолокации при принятии: $testLocationData');
          } else if (newStatus == 'выехал') {
            updateData['engineerLocationAtDeparture'] = testLocationData;
            print('[ЗАКАЗ-ГЕО] Добавлены ТЕСТОВЫЕ данные геолокации при выезде: $testLocationData');
          } else if (newStatus == 'прибыл') {
            updateData['engineerLocationAtArrival'] = testLocationData;
            print('[ЗАКАЗ-ГЕО] Добавлены ТЕСТОВЫЕ данные геолокации при прибытии: $testLocationData');
          } else if (newStatus == 'работает') {
            updateData['engineerLocationAtWork'] = testLocationData;
            print('[ЗАКАЗ-ГЕО] Добавлены ТЕСТОВЫЕ данные геолокации при начале работы: $testLocationData');
          }
        }
      }
      
      // Обновляем статус заказа
      print('[ЗАКАЗ-ГЕО] Отправляем запрос на обновление заказа со следующими данными:');
      print(updateData);
      
      // Сначала пробуем обновить только геолокацию, если она есть
      try {
        // Проверяем, есть ли данные о геолокации
        bool hasLocationData = false;
        Map<String, dynamic> locationUpdateData = {};
        
        if (updateData.containsKey('engineerLocationAtAccept')) {
          locationUpdateData['engineerLocationAtAccept'] = updateData['engineerLocationAtAccept'];
          hasLocationData = true;
        }
        if (updateData.containsKey('engineerLocationAtDeparture')) {
          locationUpdateData['engineerLocationAtDeparture'] = updateData['engineerLocationAtDeparture'];
          hasLocationData = true;
        }
        if (updateData.containsKey('engineerLocationAtArrival')) {
          locationUpdateData['engineerLocationAtArrival'] = updateData['engineerLocationAtArrival'];
          hasLocationData = true;
        }
        if (updateData.containsKey('engineerLocationAtWork')) {
          locationUpdateData['engineerLocationAtWork'] = updateData['engineerLocationAtWork'];
          hasLocationData = true;
        }
        
        // Если есть данные о геолокации, сначала обновляем только их
        if (hasLocationData) {
          print('[ЗАКАЗ-ГЕО] Сначала обновляем только данные о геолокации');
          await orderRef.update(locationUpdateData);
          print('[ЗАКАЗ-ГЕО] Геолокация успешно обновлена');
        }
        
        // Затем обновляем остальные данные заказа
        Map<String, dynamic> nonLocationData = Map.from(updateData);
        locationUpdateData.keys.forEach((key) {
          nonLocationData.remove(key);
        });
        
        print('[ЗАКАЗ-ГЕО] Обновляем остальные данные заказа: $nonLocationData');
        await orderRef.update(nonLocationData);
        print('[ЗАКАЗ-ГЕО] Заказ успешно обновлен в Firestore');
        
        // Проверяем, что данные успешно сохранены в БД
        final updatedOrder = await orderRef.get();
        if (updatedOrder.exists) {
          final updatedData = updatedOrder.data();
          print('[ЗАКАЗ-ГЕО] Проверка данных после обновления:');
          if (updatedData!.containsKey('engineerLocationAtAccept')) {
            print('[ЗАКАЗ-ГЕО] engineerLocationAtAccept: ${updatedData['engineerLocationAtAccept']}');
          }
          if (updatedData.containsKey('engineerLocationAtDeparture')) {
            print('[ЗАКАЗ-ГЕО] engineerLocationAtDeparture: ${updatedData['engineerLocationAtDeparture']}');
          }
          if (updatedData.containsKey('engineerLocationAtArrival')) {
            print('[ЗАКАЗ-ГЕО] engineerLocationAtArrival: ${updatedData['engineerLocationAtArrival']}');
          }
          if (updatedData.containsKey('engineerLocationAtWork')) {
            print('[ЗАКАЗ-ГЕО] engineerLocationAtWork: ${updatedData['engineerLocationAtWork']}');
          }
        }
      } catch (e) {
        print('[ЗАКАЗ-ГЕО] ОШИБКА при обновлении заказа: $e');
        print(StackTrace.current);
        rethrow; // Пробрасываем ошибку дальше для обработки в основном блоке try-catch
      }
      
      // Определяем новый статус для локального объекта
      TaskStatus newTaskStatus;
      switch (newStatus) {
        case 'принят':
          newTaskStatus = TaskStatus.accepted;
          break;
        case 'выехал':
          newTaskStatus = TaskStatus.onWay;
          break;
        case 'прибыл':
          newTaskStatus = TaskStatus.arrived;
          break;
        case 'работает':
          newTaskStatus = TaskStatus.working;
          break;
        case 'выполнен':
          newTaskStatus = TaskStatus.completed;
          break;
        default:
          newTaskStatus = TaskStatus.inProgress;
      }
      
      // Определяем следующее действие
      String nextAction;
      switch (newStatus) {
        case 'принят':
          nextAction = 'Выехать на заказ';
          break;
        case 'выехал':
          nextAction = 'Прибыл на объект';
          break;
        case 'прибыл':
          nextAction = 'Начать работу';
          break;
        case 'работает':
          nextAction = 'Завершить работу';
          break;
        case 'выполнен':
          nextAction = 'Заказ завершен';
          break;
        default:
          nextAction = 'Связаться с диспетчером';
      }
      
      // Обновляем таймлайн
      final Map<String, String> updatedTimeline = Map<String, String>.from(existingTimeline);
      updatedTimeline[statusText] = formattedDateTime;
      
      // Создаем новый экземпляр задачи
      final EngineerTask updatedTask = EngineerTask(
        id: orderId,
        address: address,
        status: newTaskStatus,
        clientName: clientName,
        phone: phone,
        description: description,
        cost: cost,
        timeline: updatedTimeline,
        currentAction: nextAction,
        clientId: clientId,
      );
      
      // Проверяем, что компонент всё еще есть перед обновлением состояния
      if (!mounted) {
        print('_updateOrderStatus: компонент не монтирован, состояние не будет обновлено');
        return;
      }
      
      // Обновляем состояние
      setState(() {
        _activeTask = updatedTask;
        print('Обновлен статус заказа: $newStatus, новый таймлайн: $updatedTimeline');
      });
      
      // Отправка уведомления клиенту, если у нас есть ID клиента
      if (clientId != null && clientId.isNotEmpty) {
        try {
          await _sendNotificationToClient(newStatus, statusText, orderId, clientId);
        } catch (e) {
          print('Ошибка при отправке уведомления: $e');
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Статус заказа изменен на: $statusText'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Ошибка при обновлении статуса заказа: $e');
      print(StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при обновлении статуса: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Метод для отправки уведомления клиенту
  Future<void> _sendNotificationToClient(String status, String statusText, String orderId, String clientId) async {
    try {
      print('Отправка уведомления клиенту $clientId о смене статуса на "$statusText"');
      
      // Создаем уведомление для клиента
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': clientId,
        'type': 'order_status_updated',
        'title': 'Статус заказа изменен',
        'message': 'Статус вашего заказа №$orderId изменен на "$statusText"',
        'orderId': orderId,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false
      });
      
      print('Уведомление успешно отправлено');
    } catch (e) {
      print('Ошибка при отправке уведомления клиенту: $e');
      print(StackTrace.current);
    }
  }

  // Метод для отображения диалога подтверждения статуса клиентом
  Future<bool> _showClientConfirmationDialog(String statusText) async {
    final TextEditingController codeController = TextEditingController();
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Подтверждение клиента'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Для изменения статуса на "$statusText" требуется подтверждение клиента.'),
              const SizedBox(height: 16),
              Text('Передайте устройство клиенту или свяжитесь с ним, чтобы получить код подтверждения.'),
              const SizedBox(height: 16),
              // Используем TextField напрямую здесь, без декораций
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: 'Код подтверждения',
                  hintText: 'Введите 4-значный код',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Отмена'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFD04E4E),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Подтвердить'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  // Получение текущей геолокации инженера
  Future<Map<String, dynamic>?> _getCurrentLocation() async {
    try {
      print('[ГЕОЛОКАЦИЯ] Начинаем получение геолокации инженера...');
      // Проверяем, включены ли службы геолокации
      bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('[ГЕОЛОКАЦИЯ] ОШИБКА: Службы геолокации отключены на устройстве');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Службы геолокации отключены. Включите их для определения местоположения.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return null;
      }
      print('[ГЕОЛОКАЦИЯ] Службы геолокации включены');

      // Проверяем разрешения на доступ к геолокации
      print('[ГЕОЛОКАЦИЯ] Проверяем разрешения...');
      geo.LocationPermission permission = await geo.Geolocator.checkPermission();
      print('[ГЕОЛОКАЦИЯ] Текущее разрешение: $permission');
      
      if (permission == geo.LocationPermission.denied) {
        print('[ГЕОЛОКАЦИЯ] Разрешение отклонено, запрашиваем доступ');
        permission = await geo.Geolocator.requestPermission();
        print('[ГЕОЛОКАЦИЯ] Результат запроса разрешения: $permission');
        if (permission == geo.LocationPermission.denied) {
          print('[ГЕОЛОКАЦИЯ] ОШИБКА: Разрешение на доступ к геолокации отклонено');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Разрешение на доступ к геолокации отклонено.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return null;
        }
      }

      if (permission == geo.LocationPermission.deniedForever) {
        print('[ГЕОЛОКАЦИЯ] ОШИБКА: Разрешение на доступ к геолокации отклонено навсегда');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Разрешение на доступ к геолокации отклонено навсегда. Измените настройки приложения.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }
      
      print('[ГЕОЛОКАЦИЯ] Разрешения получены, запрашиваем текущее местоположение');

      // Получаем текущее местоположение
      print('[ГЕОЛОКАЦИЯ] Вызываем geo.Geolocator.getCurrentPosition()...');
      geo.Position position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );
      
      print('[ГЕОЛОКАЦИЯ] УСПЕХ! Получены координаты: ${position.latitude}, ${position.longitude}');
      print('[ГЕОЛОКАЦИЯ] Точность: ${position.accuracy} м');
      print('[ГЕОЛОКАЦИЯ] Типы данных: lat=${position.latitude.runtimeType}, lng=${position.longitude.runtimeType}, acc=${position.accuracy.runtimeType}');
      
      // Явно преобразуем типы для гарантии совместимости с Firestore
      double latitude = position.latitude;
      double longitude = position.longitude;
      double accuracy = position.accuracy;
      
      // Возвращаем координаты в виде Map для сохранения в Firestore
      final locationData = {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      
      print('[ГЕОЛОКАЦИЯ] Подготовлены данные для записи: $locationData');
      return locationData;
    } catch (e) {
      print('[ГЕОЛОКАЦИЯ] КРИТИЧЕСКАЯ ОШИБКА при получении местоположения: $e');
      print('[ГЕОЛОКАЦИЯ] Стек ошибки:');
      print(StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при получении местоположения: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  // Виджет для отображения пустого списка заданий
  Widget _buildEmptyTasksView() {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'lib/assets/sad_red_gid.gif',
                width: 200,
                height: 200,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 20),
              Text(
                _hasNewAvailableOrders 
                    ? 'Доступны новые заказы!'
                    : 'У вас пока нет активных заявок',
                style: TextStyle(
                  fontSize: 16,
                  color: _hasNewAvailableOrders ? Colors.green : Colors.grey,
                  fontWeight: _hasNewAvailableOrders ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (_hasNewAvailableOrders) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _showAvailableOrdersDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Просмотреть доступные заказы'),
                ),
              ],
              // Добавляем дополнительное пространство снизу, чтобы контент не закрывался плавающей кнопкой
              const SizedBox(height: 80),
            ],
          ),
        ),
      ],
    );
  }

  // Виджет для отображения текущего статуса заказа с временной шкалой
  Widget _buildStatusTimeline(EngineerTask task) {
    // Список всех возможных шагов в правильном порядке
    final List<Map<String, dynamic>> allPossibleSteps = [
      {
        'status': TaskStatus.pending,
        'title': 'Назначен',
        'key': 'Назначен',
      },
      {
        'status': TaskStatus.accepted,
        'title': 'Принят',
        'key': 'Принят в работу',
      },
      {
        'status': TaskStatus.onWay,
        'title': 'Выехал',
        'key': 'Выехал на заказ',
      },
      {
        'status': TaskStatus.arrived,
        'title': 'Прибыл',
        'key': 'Прибыл на объект',
      },
      {
        'status': TaskStatus.working,
        'title': 'Работает',
        'key': 'Начал работу',
      },
      {
        'status': TaskStatus.completed,
        'title': 'Выполнен',
        'key': 'Завершил работу',
      },
    ];

    // Отладочная информация для таймлайна
    print('Таймлайн для заказа ${task.id}: ${task.timeline}');
    print('Текущий статус заказа: ${task.status}');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Отображаем все статусы, которые есть в таймлайне
          ...task.timeline.entries.map((entry) {
            final String statusText = entry.key;
            final String time = entry.value;
            
            // Добавляем дополнительную отладочную информацию
            print('Отображаем статус из таймлайна: $statusText, время: $time');
            
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  // Вертикальная линия с точкой
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD04E4E),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusText,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        time,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
          
          // Если таймлайн пустой, отображаем сообщение
          if (task.timeline.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'История статусов пуста',
                  style: TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ),
          ),
        ],
      ),
    );
  }
}

// Модель задания инженера
class EngineerTask {
  final String id;
  final String address;
  final TaskStatus status;
  final String clientName;
  final String phone;
  final String description;
  final double cost;
  final Map<String, String> timeline;
  final String currentAction;
  
  // Добавляем ID клиента для отправки уведомлений
  final String? clientId;

  EngineerTask({
    required this.id,
    required this.address,
    required this.status,
    required this.clientName,
    required this.phone,
    required this.description,
    required this.cost,
    required this.timeline,
    required this.currentAction,
    this.clientId,
  });
}

// Перечисление статусов задания
enum TaskStatus {
  pending,    // назначен
  accepted,   // принят в работу
  onWay,      // выехал на заказ
  arrived,    // прибыл на объект
  working,    // начал работу
  inProgress, // в процессе (общий статус, будет удален)
  completed,  // завершен
  rejected    // отклонен
}

// Перечисление статусов инженера
enum EngineerStatus {
  active,    // Зеленый - есть активный заказ
  inactive,  // Красный - нет активного заказа
  pending,   // Желтый - заказ на уточнении
  offline    // Серый - не в сети
}

// Профиль инженера
class EngineerProfileScreen extends StatefulWidget {
  const EngineerProfileScreen({super.key});

  @override
  State<EngineerProfileScreen> createState() => _EngineerProfileScreenState();
}

class _EngineerProfileScreenState extends State<EngineerProfileScreen> {
  // Текущий статус (для демонстрации)
  EngineerStatus _currentStatus = EngineerStatus.active;
  
  // Переменные для управления фото профиля
  File? _profileImage;
  String? _profileImageUrl;
  bool _isLoading = false;
  
  // Данные пользователя
  String _userName = '';
  DateTime? _createdAt;
  int _activity = 0;
  double _rating = 0.0;
  int _ratingCount = 0;
  
  // Список отзывов о инженере
  List<Map<String, dynamic>> _reviews = [];
  bool _isLoadingReviews = false;
  
  // Переменные для отображения всплывающего уведомления
  bool _showNotification = false;
  String _notificationMessage = '';
  Color _notificationColor = Colors.green;
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserReviews();
  }
  
  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }
  
  // Метод для отображения всплывающего уведомления
  void _showTopNotification(String message, {Color color = Colors.green}) {
    // Отменяем предыдущий таймер, если он существует
    _notificationTimer?.cancel();
    
    setState(() {
      _notificationMessage = message;
      _notificationColor = color;
      _showNotification = true;
    });
    
    // Автоматически скрываем уведомление через 3 секунды
    _notificationTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showNotification = false;
        });
      }
    });
  }
  
  // Загрузка данных пользователя из Firebase
  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final user = AuthService().currentUser;
      
      if (user != null) {
        // Проверяем, есть ли пользователь в базе
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists) {
          final userData = userDoc.data();
          if (userData != null) {
            // Загружаем путь к изображению профиля, если оно есть
            final profileImagePath = userData['profileImagePath'];
            
            // Загружаем имя пользователя
            final name = userData['name'];
            
            // Загружаем дату создания профиля
            final createdAt = userData['createdAt'];
            
            // Загружаем данные рейтинга
            final rating = userData['rating'];
            final ratingCount = userData['ratingCount'] ?? 0;
            
            // Получаем общее количество заказов инженера (активность)
            int totalOrders = 0;
            
            try {
              // 1. Считаем активные заказы в коллекции orders - строго по UID инженера
              final activeOrdersQuery = await FirebaseFirestore.instance
                  .collection('orders')
                  .where('assignedTo', isEqualTo: user.uid)
                  .get();
              
              int activeOrdersCount = activeOrdersQuery.docs.length;
              print('Найдено активных заказов для инженера с ID=${user.uid}: $activeOrdersCount');
              totalOrders += activeOrdersCount;
              
              // 2. Считаем выполненные/отмененные заказы в коллекции orders
              final completedOrdersQuery = await FirebaseFirestore.instance
                  .collection('orders')
                  .where('assignedTo', isEqualTo: user.uid)
                  .where('status', whereIn: ['выполнен', 'отменен'])
                  .get();
              
              int completedOrdersCount = completedOrdersQuery.docs.length;
              print('Найдено выполненных/отмененных заказов в коллекции orders: $completedOrdersCount');
              // Не добавляем к totalOrders, т.к. эти заказы уже учтены в activeOrdersQuery
              
              // 3. Считаем заказы в истории - строго по UID инженера
              final historyOrdersQuery = await FirebaseFirestore.instance
                  .collection('order_history')
                  .where('assignedTo', isEqualTo: user.uid)
                  .get();
              
              int historyOrdersCount = historyOrdersQuery.docs.length;
              print('Найдено заказов в истории для инженера с ID=${user.uid}: $historyOrdersCount');
              totalOrders += historyOrdersCount;
              
              print('Общее количество заказов инженера: $totalOrders');
              
              // Обновляем данные активности в Firestore
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .update({
                    'activity': totalOrders
                  });
            } catch (e) {
              print('Ошибка при получении заказов инженера: $e');
            }
            
            if (mounted) {
              setState(() {
                _profileImageUrl = profileImagePath;
                
                if (profileImagePath != null) {
                  // Проверяем, существует ли файл
                  final file = File(profileImagePath);
                  if (file.existsSync()) {
                    _profileImage = file;
                  }
                }
                
                // Устанавливаем имя
                _userName = name ?? 'Имя не указано';
                
                // Устанавливаем дату создания
                if (createdAt != null) {
                  if (createdAt is Timestamp) {
                    _createdAt = createdAt.toDate();
                  }
                }
                
                // Устанавливаем значения активности и рейтинга
                _activity = totalOrders;
                _rating = rating is num ? rating.toDouble() : 0.0;
                _ratingCount = ratingCount is num ? ratingCount.toInt() : 0;
              });
            }
          }
        }
      }
    } catch (e) {
      print('Ошибка при загрузке данных пользователя: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // Метод для загрузки отзывов об инженере
  Future<void> _loadUserReviews() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingReviews = true;
    });
    
    try {
      final user = AuthService().currentUser;
      if (user == null) {
        setState(() {
          _isLoadingReviews = false;
          _reviews = [];
        });
        return;
      }
      
      print('Загрузка отзывов для инженера с ID: ${user.uid}');
      
      // Получаем отзывы, оставленные клиентами для этого инженера
      final reviewsSnapshot = await FirebaseFirestore.instance
          .collection('reviews')
          .where('engineerId', isEqualTo: user.uid)
          .where('type', isEqualTo: 'client_to_engineer')
          .orderBy('createdAt', descending: true)
          .get();
          
      print('Найдено отзывов: ${reviewsSnapshot.docs.length}');
      
      final reviews = reviewsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'clientName': data['clientName'] ?? 'Неизвестный клиент',
          'rating': data['rating'] ?? 0,
          'comment': data['comment'] ?? '',
          'createdAt': data['createdAt']?.toDate() ?? DateTime.now(),
        };
      }).toList();
      
      // Если нужно, обновляем рейтинг инженера на основе полученных отзывов
      _updateEngineerRating(reviews);
      
      if (mounted) {
        setState(() {
          _reviews = reviews;
          _isLoadingReviews = false;
        });
      }
    } catch (e) {
      print('Ошибка при загрузке отзывов: $e');
      if (mounted) {
        setState(() {
          _isLoadingReviews = false;
        });
      }
    }
  }

  // Метод для обновления рейтинга инженера
  Future<void> _updateEngineerRating(List<Map<String, dynamic>> reviews) async {
    try {
      if (reviews.isEmpty) return;
      
      // Вычисляем средний рейтинг
      double totalRating = 0;
      int count = 0;
      
      for (final review in reviews) {
        final rating = review['rating'] as int?;
        if (rating != null) {
          totalRating += rating;
          count++;
        }
      }
      
      if (count > 0) {
        final averageRating = totalRating / count;
        
        final user = AuthService().currentUser;
        if (user != null) {
          // Обновляем рейтинг в Firestore
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
                'rating': averageRating,
                'ratingCount': count,
              });
          
          // Обновляем локальное состояние
          if (mounted) {
            setState(() {
              _rating = averageRating;
              _ratingCount = count;
            });
          }
          
          print('Обновлен рейтинг инженера: $averageRating ($count отзывов)');
        }
      }
    } catch (e) {
      print('Ошибка при обновлении рейтинга инженера: $e');
    }
  }

  // Метод для выбора изображения из галереи
  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedImage = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (pickedImage != null) {
        setState(() {
          _profileImage = File(pickedImage.path);
        });
        
        // Сохранить изображение в Firebase Storage и обновить профиль
        await _saveProfileImage();
      }
    } catch (e) {
      if (mounted) {
        _showTopNotification('Ошибка выбора изображения: $e', color: Colors.red);
      }
    }
  }
  
  // Сохранение изображения в Firestore
  Future<void> _saveProfileImage() async {
    if (_profileImage == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final user = AuthService().currentUser;
      
      if (user != null) {
        // Для тестирования просто сохраняем локальный путь
        final String localPath = _profileImage!.path;
        
        // Используем set вместо update, чтобы создать документ, если его нет
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
              'profileImagePath': localPath,
              'updatedAt': FieldValue.serverTimestamp(),
              'uid': user.uid, // Добавляем uid, чтобы документ точно содержал эти данные
              'email': user.email ?? '', // Добавляем email, если он доступен
              'name': _userName, // Сохраняем текущее имя пользователя
              // Сохраняем createdAt только если документ новый
              'createdAt': _createdAt ?? FieldValue.serverTimestamp(),
              // Сохраняем активность и рейтинг
              'activity': _activity,
              'rating': _rating,
            }, SetOptions(merge: true)); // merge: true позволяет обновить только указанные поля
            
        setState(() {
          _profileImageUrl = localPath;
        });
        
        // Показываем всплывающее уведомление
        _showTopNotification('Изображение профиля обновлено');
      }
    } catch (e) {
      print('Ошибка при сохранении изображения профиля: $e');
      _showTopNotification('Ошибка при сохранении изображения: $e', color: Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Получение цвета обводки в зависимости от статуса
  Color _getStatusColor(EngineerStatus status) {
    switch (status) {
      case EngineerStatus.active:
        return Colors.green;
      case EngineerStatus.inactive:
        return Colors.red;
      case EngineerStatus.pending:
        return Colors.amber;
      case EngineerStatus.offline:
        return Colors.grey;
    }
  }

  // Получение текста статуса в зависимости от статуса
  String _getStatusText(EngineerStatus status) {
    switch (status) {
      case EngineerStatus.active:
        return 'В работе';
      case EngineerStatus.inactive:
        return 'Нет заказов';
      case EngineerStatus.pending:
        return 'На уточнении';
      case EngineerStatus.offline:
        return 'Не в сети';
    }
  }

  // Переключение на следующий статус для демонстрации
  void _toggleStatus() {
    setState(() {
      switch (_currentStatus) {
        case EngineerStatus.active:
          _currentStatus = EngineerStatus.inactive;
          break;
        case EngineerStatus.inactive:
          _currentStatus = EngineerStatus.pending;
          break;
        case EngineerStatus.pending:
          _currentStatus = EngineerStatus.offline;
          break;
        case EngineerStatus.offline:
          _currentStatus = EngineerStatus.active;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Определяем текущий статус
    final Color statusColor = _getStatusColor(_currentStatus);
    final String statusText = _getStatusText(_currentStatus);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      // Аватар с цветной рамкой и свечением
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Статус с динамическим цветом
                                GestureDetector(
                                  onTap: _toggleStatus, // Добавляем возможность переключения статуса для демонстрации
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          statusText,
                                          style: TextStyle(
                                            color: statusColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Кнопка выхода
                                IconButton(
                                  icon: const Icon(Icons.logout, color: Colors.red),
                                  onPressed: () async {
                                    try {
                                      await AuthService().signOut();
                                      if (context.mounted) {
                                        Navigator.pushReplacementNamed(context, '/login');
                                      }
                                    } catch (e) {
                                      print('Ошибка при выходе: $e');
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: Stack(
                                children: [
                                  // Добавляем свечение вокруг аватара
                                  Container(
                                    width: 104,
                                    height: 104,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: statusColor.withOpacity(0.5),
                                          blurRadius: 15,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Аватар с обводкой динамического цвета
                                  GestureDetector(
                                    onTap: _toggleStatus, // Добавляем возможность переключения статуса для демонстрации
                                    child: Container(
                                      width: 100,
                                      height: 100,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                        border: Border.all(
                                          color: statusColor,
                                          width: 3,
                                        ),
                                      ),
                                      child: ClipOval(
                                        child: _profileImage != null
                                          ? Image.file(
                                              _profileImage!,
                                              fit: BoxFit.cover,
                                            )
                                          : const Icon(
                                              Icons.person,
                                              size: 60,
                                              color: Colors.grey,
                                            ),
                                      ),
                                    ),
                                  ),
                                  // Кнопка для изменения фото профиля
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: _pickImage,
                                      child: Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.2),
                                              blurRadius: 4,
                                              spreadRadius: 0,
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.camera_alt,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _userName,
                                  style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              textAlign: TextAlign.center,
                                ),
                                const SizedBox(width: 8),
                                // Кнопка редактирования имени
                                GestureDetector(
                                  onTap: _editName,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.edit,
                                      color: Colors.black,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Инженер 1-го разряда',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            
                            // Статистика в три колонки
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    _ratingCount > 0 
                                        ? "${_rating.toStringAsFixed(1)} (${_ratingCount})"
                                        : "Нет отзывов",
                                    'Рейтинг'
                                  ),
                                ),
                                Expanded(
                                  child: _buildStatCard(
                                    _createdAt != null
                                        ? '${_createdAt!.day}.${_createdAt!.month}.${_createdAt!.year}'
                                        : 'Нет данных',
                                    'Дата регистрации'
                                  ),
                                ),
                                Expanded(
                                  child: _buildStatCard(
                                    _activity.toString(),
                                    'Активность'
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 24),
                            
                            // Текущий заказ
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                'Текущий заказ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Отзывы заголовок
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Отзывы',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  if (_reviews.isNotEmpty)
                                    Text(
                                      'Всего: ${_reviews.length}',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            
                            const SizedBox(height: 12),
                            
                            // Отзывы карточки
                            _isLoadingReviews
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: CircularProgressIndicator(color: Colors.red),
                                  ),
                                )
                              : _reviews.isEmpty
                                ? _buildEmptyReviewsMessage()
                                : Container(
                                    height: 250, // Высота для двух строк отзывов
                                    child: ListView.builder(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _reviews.length,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      itemBuilder: (context, index) {
                                        return Container(
                                          width: MediaQuery.of(context).size.width * 0.8,
                                          margin: const EdgeInsets.only(right: 12),
                                          child: Column(
                                            children: [
                                              // Верхний отзыв
                                              Expanded(
                                                child: _buildReviewCard(
                                                  _reviews[index]['clientName'],
                                                  _reviews[index]['comment'],
                                                  _reviews[index]['rating'],
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              // Нижний отзыв (если есть достаточно отзывов)
                                              Expanded(
                                                child: _reviews.length > index + 1
                                                  ? _buildReviewCard(
                                                      _reviews[(index + _reviews.length/2).floor() % _reviews.length]['clientName'],
                                                      _reviews[(index + _reviews.length/2).floor() % _reviews.length]['comment'],
                                                      _reviews[(index + _reviews.length/2).floor() % _reviews.length]['rating'],
                                                    )
                                                  : Container(
                                                      decoration: BoxDecoration(
                                                        color: Colors.black.withOpacity(0.3),
                                                        borderRadius: BorderRadius.circular(12),
                                                        border: Border.all(color: Colors.grey[800]!, width: 1),
                                                      ),
                                                      child: Center(
                                                        child: Text(
                                                          'Больше отзывов пока нет',
                                                          style: TextStyle(
                                                            color: Colors.grey[400],
                                                            fontSize: 12,
                                                          ),
                                                          textAlign: TextAlign.center,
                                                        ),
                                                      ),
                                                    ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                            
                            const SizedBox(height: 70), // Место для навигационной панели
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          // Индикатор загрузки
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.red,
                  ),
                ),
              ),
            ),
          
          // Всплывающее уведомление
          if (_showNotification)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              right: 16,
              child: AnimatedOpacity(
                opacity: _showNotification ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _notificationColor,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _notificationColor == Colors.green 
                            ? Icons.check_circle 
                            : Icons.error,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _notificationMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          setState(() {
                            _showNotification = false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Карточка статистики
  Widget _buildStatCard(String value, String label) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Карточка отзыва
  Widget _buildReviewCard(String name, String text, int rating) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber, width: 2),
                ),
                child: const Center(
                  child: Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: List.generate(
                        5,
                        (index) => Icon(
                          Icons.star,
                          color: index < rating ? Colors.amber : Colors.grey[700],
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 13,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Метод для редактирования имени
  void _editName() async {
    // Создаем контроллер с текущим именем
    final TextEditingController nameController = TextEditingController(text: _userName);
    
    // Показываем диалог для редактирования
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Редактирование имени'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Имя',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              // Сохраняем новое имя, если оно не пустое
              if (nameController.text.trim().isNotEmpty) {
                setState(() {
                  _userName = nameController.text.trim();
                  _isLoading = true;
                });
                
                try {
                  final user = AuthService().currentUser;
                  
                  if (user != null) {
                    // Обновляем имя в Firestore
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .set({
                          'name': _userName,
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                    
                    _showTopNotification('Имя успешно обновлено');
                  }
                } catch (e) {
                  print('Ошибка при обновлении имени: $e');
                  _showTopNotification('Ошибка при обновлении имени: $e', color: Colors.red);
                } finally {
                  setState(() {
                    _isLoading = false;
                  });
                }
                
                // Закрываем диалог
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  // Сообщение, если нет отзывов
  Widget _buildEmptyReviewsMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Icon(
            Icons.rate_review_outlined,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 8),
          const Text(
            'У вас пока нет отзывов',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Отзывы появятся после выполнения заказов',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// Модель уведомления
class Notification {
  final String id;
  final String title;
  final String message;
  final String time;
  bool isRead;

  Notification({
    required this.id,
    required this.title,
    required this.message,
    required this.time,
    required this.isRead,
  });
}

// Функция для проверки корректности перехода между статусами
bool _isValidStatusTransition(String currentStatus, String newStatus) {
  // Словарь допустимых переходов
  final Map<String, List<String>> validTransitions = {
    'назначен': ['принят'],
    'принят': ['выехал'],
    'выехал': ['прибыл'],
    'прибыл': ['работает'],
    'работает': ['выполнен'],
  };
  
  // Проверка наличия текущего статуса в словаре и возможности перехода
  if (validTransitions.containsKey(currentStatus)) {
    return validTransitions[currentStatus]!.contains(newStatus);
  }
  
  return false;
}

// Модель доступного заказа
class AvailableOrder {
  final String id;
  final String title;
  final String address;
  final String clientName;
  final double price;
  final String service;
  final bool isNew;
  final DateTime? createdAt;

  AvailableOrder({
    required this.id,
    required this.title,
    required this.address,
    required this.clientName,
    required this.price,
    required this.service,
    required this.isNew,
    this.createdAt,
  });
}