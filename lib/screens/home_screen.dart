import 'package:flutter/material.dart';
import 'dart:math' as math; // Используем только один импорт math с псевдонимом
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/auth_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'order_history_screen.dart';

// Функция для генерации случайного 4-значного кода
String _generateConfirmationCode() {
  final random = math.Random(); // Используем math.Random() из импорта с псевдонимом
  // Генерируем число от 1000 до 9999
  return (1000 + random.nextInt(9000)).toString();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // Индекс выбранной категории
  int _selectedCategoryIndex = 0;
  // Контроллер для поля поиска
  final TextEditingController _searchController = TextEditingController();
  // Строка поиска
  String _searchQuery = '';
  // Список отфильтрованных услуг
  List<Map<String, dynamic>> _filteredServices = [];
  // Контроллер анимации для пульсации выбранной категории
  AnimationController? _pulseController;
  // Контроллер анимации для эффекта при фильтрации
  AnimationController? _filterAnimationController;
  // Анимация для эффекта при фильтрации
  Animation<double>? _filterAnimation;
  // Контроллер анимации для появления карточек
  AnimationController? _appearController;
  // Показывать ли анимацию появления карточек
  bool _showCardAnimations = true;
  // Контроллер скролла для сетки услуг
  final ScrollController _gridScrollController = ScrollController();
  // Позиция скролла для анимации индикатора
  double _scrollOffset = 0.0;
  
  // Переменные для местоположения и адреса
  Position? _currentPosition;
  String _currentAddress = 'Определение адреса...';
  bool _isLoadingLocation = false;
  
  // Контроллер для поля дополнительной информации
  final TextEditingController _additionalInfoController = TextEditingController();
  
  // Список категорий услуг (будет загружаться из Firebase)
  List<Map<String, dynamic>> _categoryList = [];
  
  // Флаг загрузки данных
  bool _isLoading = false;
  
  // Флаг использования для refresh indicator
  bool _isRefreshing = false;

  // Список услуг (будет загружаться из Firebase)
  List<Map<String, dynamic>> _services = [];
  
  // Список категорий услуг
  List<String> _categories = [];

  // Переменные для хранения данных карты при выборе оплаты картой
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _cardExpiryController = TextEditingController();
  final TextEditingController _cardCvcController = TextEditingController();
  final TextEditingController _cardHolderController = TextEditingController();
  
  // Переменные для хранения данных пользователя
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _userEmailController = TextEditingController();
  final TextEditingController _userPhoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Инициализация списка отфильтрованных услуг
    _filteredServices = [];
    
    // Добавляем слушатель изменений текста поиска с задержкой для снижения нагрузки
    _searchController.addListener(() {
      // Используем debounce для уменьшения количества обновлений
      if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        _filterServices();
      });
    });
    
    // Инициализация контроллера пульсации с меньшей частотой обновления
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000), // Увеличиваем до 2 секунд
    );
    
    // Инициализация контроллера анимации фильтрации
    _filterAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    
    _filterAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _filterAnimationController!,
        curve: Curves.easeInOut,
      ),
    );
    
    // Инициализация контроллера анимации появления карточек
    _appearController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    // Сразу запускаем анимацию для отображения карточек
    _filterAnimationController?.forward();
    
    // Загрузка данных из Firestore
    _loadData();
    
    // Предварительно заполняем данные пользователя из AuthService
    _fillUserData();
    
    // Отложенный запуск анимации появления для уменьшения нагрузки при запуске
    Future.microtask(() {
      _startAppearAnimation();
    });
    
    // Отключаем предварительную загрузку GIF для снижения нагрузки при запуске
    _showCardAnimations = false; // По умолчанию отключаем анимации
    
    // Безопасно предзагружаем GIF после инициализации виджета
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Добавляем отслеживание положения скролла
      _gridScrollController.addListener(() {
        if (_gridScrollController.hasClients) {
          final scrollPosition = _gridScrollController.position;
          final scrollOffset = scrollPosition.pixels;
          
          // Обновляем значение скролла для анимации индикатора
          if (scrollOffset < 0) {
            setState(() {
              _scrollOffset = scrollOffset;
            });
          }
        }
      });
    });
    
    // Запускаем пульсацию только если приложение не на медленном устройстве
    // и делаем это с задержкой для улучшения производительности при запуске
    Future.delayed(const Duration(milliseconds: 500), () {
      // Проверяем производительность устройства и решаем, стоит ли включать анимации
      final isHighPerformanceDevice = WidgetsBinding.instance.renderView.configuration.devicePixelRatio >= 3.0;
      
      setState(() {
        _showCardAnimations = isHighPerformanceDevice;
      });
      
      if (isHighPerformanceDevice) {
        _pulseController?.repeat(reverse: true);
      }
    });
  }

  // Добавляем таймер для debounce
  Timer? _debounceTimer;

  @override
  void dispose() {
    // Освобождаем другие ресурсы контроллера
    _searchController.removeListener(_filterServices);
    _searchController.dispose();
    _pulseController?.dispose();
    _filterAnimationController?.dispose();
    _appearController?.dispose();
    _gridScrollController.dispose();
    _additionalInfoController.dispose();
    _userNameController.dispose();
    _userEmailController.dispose();
    _userPhoneController.dispose();
    _cardNumberController.dispose();
    _cardExpiryController.dispose();
    _cardCvcController.dispose();
    _cardHolderController.dispose();
    _debounceTimer?.cancel(); // Отменяем таймер
    super.dispose();
  }

  // Метод для фильтрации услуг по поисковому запросу
  void _filterServices() {
    // Запускаем анимацию фильтрации
    _filterAnimationController?.reset();
    _filterAnimationController?.forward();
    
    setState(() {
      _searchQuery = _searchController.text.toLowerCase().trim();
      // Включаем анимацию только если мы не определили, что устройство медленное
      if (WidgetsBinding.instance.renderView.configuration.devicePixelRatio >= 3.0) {
        _showCardAnimations = true;
      }
      
      if (_searchQuery.isEmpty) {
        // Если поисковый запрос пуст, показываем все услуги
        _filteredServices = _filterByCategory(List.from(_services));
      } else {
        // Фильтруем услуги по названию
        _filteredServices = _filterByCategory(_services.where((service) => 
          service['title'].toString().toLowerCase().contains(_searchQuery)
        ).toList());
      }
    });
    
    // Запускаем анимацию появления
    _startAppearAnimation();
  }

  // Метод для фильтрации услуг по выбранной категории
  List<Map<String, dynamic>> _filterByCategory(List<Map<String, dynamic>> services) {
    if (_categoryList.isEmpty || _selectedCategoryIndex >= _categoryList.length) {
      return services;
    }
    
    // Получаем ID выбранной категории
    final selectedCategoryId = _categoryList[_selectedCategoryIndex]['id'];
    
    // Фильтруем услуги по ID категории
    return services.where((service) => 
      service['categoryId'] == selectedCategoryId
    ).toList();
  }

  // Метод для запуска поиска по кнопке
  void _performSearch() {
    // Обновляем список отфильтрованных услуг
    _filterServices();
    // Убираем клавиатуру
    FocusScope.of(context).unfocus();
  }

  // Метод для запуска анимации появления карточек
  void _startAppearAnimation() {
    if (_showCardAnimations) {
      _appearController?.reset();
      _appearController?.forward();
    }
  }

  // Метод для обновления данных при свайпе вниз
  Future<void> _refreshData() async {
    try {
      print('Начинаем обновление данных...');
      setState(() {
        _isRefreshing = true;
      });
      
      // Загружаем актуальные данные из Firestore
      await _loadData();
      
      if (!mounted) return; // Проверяем, что виджет все еще в дереве виджетов
      
      print('Обновление данных завершено');
      
    } catch (e) {
      print('Ошибка при обновлении данных: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  // Метод для запуска обновления данных
  Future<void> _startRefresh() async {
    if (_isRefreshing) return;
    return _refreshData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isLoading 
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: const Color(0xFFD04E4E),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Загрузка данных...',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
          onRefresh: _refreshData,
          color: const Color(0xFFD04E4E), // Цвет индикатора
          backgroundColor: const Color(0xFF1E1E1E), // Фон индикатора
          child: CustomScrollView(
            controller: _gridScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Поиск (верхняя панель)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFD04E4E),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Поле поиска
                        Expanded(
                          flex: 7,
                          child: Container(
                            height: 50,
                            decoration: const BoxDecoration(
                              color: Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(10),
                                bottomLeft: Radius.circular(10),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.search, color: Colors.white, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: 'Найти услугу',
                                      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                                      border: InputBorder.none,
                                    ),
                                    onSubmitted: (_) => _performSearch(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Кнопка поиска
                        Expanded(
                          flex: 3,
                          child: Container(
                            height: 50,
                            decoration: const BoxDecoration(
                              color: Color(0xFFD04E4E),
                              borderRadius: BorderRadius.only(
                                topRight: Radius.circular(10),
                                bottomRight: Radius.circular(10),
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _performSearch,
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(10),
                                  bottomRight: Radius.circular(10),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Поиск',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16,
                                    ),
                                  ),
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
              
              // Отступ
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              
              // Категории услуг
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFD04E4E),
                        width: 1.5,
                      ),
                    ),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      itemBuilder: (context, index) {
                        final isSelected = _selectedCategoryIndex == index;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedCategoryIndex = index;
                              // При смене категории обновляем список отфильтрованных услуг
                              _filterServices();
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            // Динамическая ширина в зависимости от длины текста, с минимальной шириной
                            width: (_categories[index].length * 10.0 + 32.0).clamp(80.0, 140.0),
                            height: 40,
                            margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFD04E4E) : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: isSelected ? [
                                BoxShadow(
                                  color: const Color(0xFFD04E4E).withOpacity(
                                    0.3 + 0.2 * (_pulseController?.value ?? 0.0), // Пульсирующая прозрачность тени
                                  ),
                                  blurRadius: 4 + 2 * (_pulseController?.value ?? 0.0), // Пульсирующее размытие тени
                                  spreadRadius: 0.5 * (_pulseController?.value ?? 0.0), // Пульсирующее распространение тени
                                  offset: const Offset(0, 2),
                                ),
                              ] : null,
                            ),
                            child: Text(
                              _categories[index],
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1, // Запрещаем перенос на новую строку
                              overflow: TextOverflow.ellipsis, // При необходимости обрезаем текст с многоточием
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              
              // Отступ
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              
                  // Проверяем, пустой ли список услуг
                  _filteredServices.isEmpty
                      ? SliverToBoxAdapter(
                          child: _buildEmptyServicesView(),
                        )
                      : SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 75),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 160 / 240,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final service = _filteredServices[index];
                      
                      // Упрощаем анимацию для повышения производительности
                      if (!_showCardAnimations) {
                        return _buildServiceCard(
                          title: service['title'],
                          price: (service['price'] as int).toDouble(),
                          currency: service['currency'],
                          discount: service['discount'],
                          image: service['image'],
                          description: service['description'] as String?,
                          features: service['features'] != null 
                              ? List<String>.from(service['features'] as List) 
                              : null,
                        );
                      }
                      
                      // Используем AnimatedBuilder только если включены анимации
                      return AnimatedBuilder(
                        animation: _appearController ?? const AlwaysStoppedAnimation(1.0),
                        builder: (context, child) {
                          // Рассчитываем задержку анимации (каскад)
                          final delay = (index % 8) * 0.1;
                          final animValue = math.min(1.0, (_appearController?.value ?? 1.0) - delay).clamp(0.0, 1.0);
                          
                          // Применяем только анимацию движения, без прозрачности
                          return Transform.translate(
                            offset: Offset(0, (1 - Curves.easeOutCubic.transform(animValue)) * 30),
                            child: child,
                          );
                        },
                        child: _buildServiceCard(
                          title: service['title'],
                          price: (service['price'] as int).toDouble(),
                          currency: service['currency'],
                          discount: service['discount'],
                          image: service['image'],
                          description: service['description'] as String?,
                          features: service['features'] != null 
                              ? List<String>.from(service['features'] as List) 
                              : null,
                        ),
                      );
                    },
                    childCount: _filteredServices.length,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Метод для отображения элемента, когда список услуг пуст
  Widget _buildEmptyServicesView() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  spreadRadius: 2,
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'lib/assets/sad_red_gid.gif',
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 30),
          Text(
            _searchQuery.isNotEmpty 
                ? 'По запросу "$_searchQuery" ничего не найдено' 
                : (_categoryList.isNotEmpty && _selectedCategoryIndex < _categoryList.length)
                    ? 'В категории "${_categories[_selectedCategoryIndex]}" нет услуг' 
                    : 'Нет доступных услуг',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2D2D2D),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 15),
          const Text(
            'Попробуйте выбрать другую категорию или изменить поисковый запрос',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF6D6D6D),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _searchController.clear();
                _searchQuery = '';
                if (_categoryList.isNotEmpty) {
                  _selectedCategoryIndex = 0;
                }
                _filterServices();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD04E4E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Сбросить фильтр',
              style: TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
  
  Widget _buildServiceCard({
    required String title,
    required double price,
    required String currency,
    int? discount,
    required String image,
    String? description,
    List<String>? features,
  }) {
    // ОСНОВНОЙ КОНТЕЙНЕР КАРТОЧКИ УСЛУГИ
    return InkWell(
      onTap: () {
        // Открываем окно с подробной информацией при нажатии на карточку
        _showServiceDetails(
          title: title,
          price: price,
          currency: currency,
          image: image,
          description: description ?? 'Нет описания',
          features: features ?? [],
        );
      },
      borderRadius: BorderRadius.circular(16), // Скругление эффекта нажатия
      child: Container(
        width: 160, // Ширина карточки
        height: 240, // Увеличиваем высоту карточки для предотвращения переполнения
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E), // Цвет фона карточки
          borderRadius: BorderRadius.circular(16), // Скругление углов
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15), // Уменьшаем прозрачность тени
              blurRadius: 10, // Размытие тени
              spreadRadius: 0, // Распространение тени
              offset: const Offset(0, 4), // Смещение тени (x, y)
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. ИЗОБРАЖЕНИЕ УСЛУГИ - Верхняя часть карточки
            Padding(
              padding: const EdgeInsets.all(10), // Немного уменьшаем отступы для экономии места
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12), // Скругление углов изображения
                child: SizedBox(
                  height: 85, // Немного уменьшаем высоту изображения для экономии места
                  child: Image.asset(
                    image,
                    fit: BoxFit.cover, // Способ заполнения изображения: cover заполняет всю площадь
                  ),
                ),
              ),
            ),
            
            // 2. НАЗВАНИЕ УСЛУГИ - Текст под изображением
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12), // Боковые отступы для текста
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFA5A5A5), // Серый цвет текста названия (A5A5A5)
                  fontSize: 14, // Размер шрифта - уменьшите, если текст слишком длинный
                  fontWeight: FontWeight.w400, // Толщина шрифта: 400=normal, 700=bold
                ),
                textAlign: TextAlign.left, // Выравнивание текста по левому краю
                maxLines: 2, // Разрешаем две строки для отображения полного названия
              ),
            ),
            
            // 3. ЦЕНА - Отображается под названием
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), // Отступы вокруг цены
              child: Text(
                "${price.toInt()} $currency",
                style: const TextStyle(
                  color: Colors.white, // Белый цвет для цены
                  fontWeight: FontWeight.bold, // Жирный шрифт
                  fontSize: 18, // Размер шрифта цены - измените для другого размера
                ),
                textAlign: TextAlign.left, // Прижимаем цену к левому краю
              ),
            ),
            
            // Заполнитель пространства - чтобы кнопка "Заказать" была внизу карточки
            const Spacer(), // Добавляем пространство, чтобы кнопка была внизу
            
            // 4. КНОПКА "ЗАКАЗАТЬ" - Нижняя часть карточки
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10), // Уменьшаем боковые отступы для более широкой кнопки
              child: Container(
                height: 36, // Высота кнопки - увеличьте для более крупной кнопки
                decoration: const BoxDecoration(
                  color: Color(0xFFD04E4E), // Красный цвет фона кнопки
                  borderRadius: BorderRadius.all(Radius.circular(8)), // Скругление углов кнопки
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _showOrderForm(
                        title: title,
                        price: price,
                        currency: currency,
                        description: description ?? 'Нет описания',
                        features: features ?? [],
                      );
                    },
                    borderRadius: const BorderRadius.all(Radius.circular(8)), // Скругление эффекта нажатия
                    child: const Center(
                      child: Text(
                        "Заказать",
                        style: TextStyle(
                          color: Colors.white, // Цвет текста кнопки
                          fontWeight: FontWeight.bold, // Жирный шрифт
                          fontSize: 14, // Размер шрифта кнопки
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Метод для показа анимированного эффекта при нажатии на кнопку "Заказать"
  void _showButtonPressAnimation(BuildContext context) {
    // Создаем временный контроллер анимации
    final buttonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    // Анимация масштаба
    final scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: buttonAnimController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Создаем оверлей для отображения анимированного эффекта
    final overlay = OverlayEntry(
      builder: (context) => AnimatedBuilder(
        animation: buttonAnimController,
        builder: (context, child) {
          return Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFD04E4E).withOpacity(0.3 * buttonAnimController.value),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.check_circle_outline,
                  color: Colors.white.withOpacity(buttonAnimController.value),
                  size: 50,
                ),
              ),
            ),
          );
        },
      ),
    );
    
    // Запускаем анимацию
    buttonAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 300), () {
          overlay.remove();
          buttonAnimController.dispose();
        });
      }
    });
    
    Overlay.of(context).insert(overlay);
    buttonAnimController.forward();
  }

  // Метод для отображения подробной информации об услуге
  void _showServiceDetails({
    required String title,
    required double price,
    required String currency,
    required String image,
    required String description,
    required List<String> features,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
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
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            
            // Изображение услуги с названием
            SizedBox(
              height: 180,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Изображение
                  Image.asset(
                    image,
                    fit: BoxFit.cover,
                  ),
                  // Затемнение с градиентом
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.8),
                        ],
                      ),
                    ),
                  ),
                  // Название и цена
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "$price $currency",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            // Кнопка "Заказать"
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _showOrderForm(
                                  title: title,
                                  price: price,
                                  currency: currency,
                                  description: description,
                                  features: features,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD04E4E),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: const Text("Заказать"),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Основное содержимое
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Описание
                    const Text(
                      "Описание",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 16,
                      ),
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Особенности услуги
                    if (features.isNotEmpty) ...[
                      const Text(
                        "Особенности",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...features.map((feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 6, right: 10),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFFD04E4E),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                feature,
                                style: TextStyle(
                                  color: Colors.grey[300],
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ],
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Метод для отображения формы заказа
  void _showOrderForm({
    required String title,
    required double price,
    required String currency,
    required String description,
    required List<String> features,
  }) {
    // Очищаем контроллер для дополнительной информации
    _additionalInfoController.clear();
    
    // Переменная для хранения выбранного способа оплаты
    String _selectedPaymentMethod = 'qr';
    
    // Переменная для отслеживания состояния описания (свернуто/развернуто)
    bool _isDescriptionExpanded = false;
    
    // Переменная для отслеживания валидности формы
    bool _isFormValid = false;
    
    // Получаем текущее местоположение, если оно еще не получено
    if (_currentPosition == null) {
      _getCurrentLocation();
    }
    
    // Функция для проверки валидности формы
    void _validateForm(StateSetter setState) {
      // Проверяем адрес доставки
      bool isAddressValid = _currentPosition != null && 
                           _currentAddress.isNotEmpty && 
                           _currentAddress != 'Определение адреса...' &&
                           !_currentAddress.contains('Ошибка') &&
                           !_currentAddress.contains('отключены') &&
                           !_currentAddress.contains('Нет разрешения') &&
                           !_currentAddress.contains('запрещено');
      
      // Проверяем данные пользователя
      bool isUserDataValid = _userNameController.text.isNotEmpty &&
                            _userEmailController.text.isNotEmpty && 
                            _userEmailController.text.contains('@') &&
                            _userPhoneController.text.isNotEmpty && 
                            _userPhoneController.text.length >= 10;
      
      // По умолчанию форма валидна, если адрес и данные пользователя заполнены
      bool isValid = isAddressValid && isUserDataValid;
      
      // Обновляем статус валидности формы
      setState(() {
        _isFormValid = isValid;
      });
    }
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          // Сохраняем ссылку на StateSetter для использования в других методах
          StateSetter? stateSetter = setState;
          
          // Вызываем проверку валидности при каждой перерисовке
          _validateForm(setState);
          
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
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
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                
                // Заголовок формы
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    "Оформление заказа",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                // Основное содержимое формы заказа
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Информация о выбранной услуге
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D2D2D),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Информация о заказе",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  // Иконка для разворачивания/сворачивания описания
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _isDescriptionExpanded = !_isDescriptionExpanded;
                                      });
                                    },
                                    child: AnimatedRotation(
                                      turns: _isDescriptionExpanded ? 0.5 : 0.0,
                                      duration: const Duration(milliseconds: 300),
                                      child: Icon(
                                        Icons.keyboard_arrow_down,
                                        color: _isDescriptionExpanded 
                                            ? const Color(0xFFD04E4E)
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Услуга:",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Flexible(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.end,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Стоимость:",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    "${price.toInt()} $currency",
                                    style: const TextStyle(
                                      color: Color(0xFFD04E4E),
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              // Анимированное описание заказа
                              ClipRect(
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                  child: AnimatedOpacity(
                                    opacity: _isDescriptionExpanded ? 1.0 : 0.0,
                                    duration: const Duration(milliseconds: 200),
                                    child: Container(
                                      height: _isDescriptionExpanded ? null : 0,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 16),
                                          const Divider(color: Colors.grey),
                                          const SizedBox(height: 8),
                                          const Text(
                                            "Описание:",
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            description,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (features.isNotEmpty) ...[
                                            const SizedBox(height: 16),
                                            const Text(
                                              "Особенности:",
                                              style: TextStyle(
                                                color: Colors.grey,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            ...features.map((feature) => Padding(
                                              padding: const EdgeInsets.only(bottom: 4),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Icon(
                                                    Icons.check_circle,
                                                    color: Color(0xFFD04E4E),
                                                    size: 16,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      feature,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )).toList(),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Персональные данные
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D2D2D),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Персональные данные",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              // Поле для имени
                              TextField(
                                controller: _userNameController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Имя',
                                  labelStyle: TextStyle(color: Colors.grey[400]),
                                  hintText: 'Введите ваше имя',
                                  hintStyle: TextStyle(color: Colors.grey[600]),
                                  filled: true,
                                  fillColor: const Color(0xFF1E1E1E),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.person,
                                    color: Colors.grey,
                                  ),
                                ),
                                onChanged: (_) {
                                  _validateForm(setState);
                                },
                              ),
                              
                              const SizedBox(height: 12),
                              
                              // Поле для email
                              TextField(
                                controller: _userEmailController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  labelStyle: TextStyle(color: Colors.grey[400]),
                                  hintText: 'Введите ваш email',
                                  hintStyle: TextStyle(color: Colors.grey[600]),
                                  filled: true,
                                  fillColor: const Color(0xFF1E1E1E),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.email,
                                    color: Colors.grey,
                                  ),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                onChanged: (_) {
                                  _validateForm(setState);
                                },
                              ),
                              
                              const SizedBox(height: 12),
                              
                              // Поле для телефона
                              TextField(
                                controller: _userPhoneController,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  labelText: 'Телефон',
                                  labelStyle: TextStyle(color: Colors.grey[400]),
                                  hintText: 'Введите ваш телефон',
                                  hintStyle: TextStyle(color: Colors.grey[600]),
                                  filled: true,
                                  fillColor: const Color(0xFF1E1E1E),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.phone,
                                    color: Colors.grey,
                                  ),
                                ),
                                keyboardType: TextInputType.phone,
                                onChanged: (_) {
                                  _validateForm(setState);
                                },
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Информация о местоположении
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D2D2D),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "Адрес доставки",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (_isLoadingLocation)
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Color(0xFFD04E4E),
                                        strokeWidth: 2,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _currentAddress,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () async {
                                  // Обновляем местоположение и статус валидации формы
                                  await _getCurrentLocation();
                                  _validateForm(setState);
                                },
                                icon: const Icon(
                                  Icons.refresh,
                                  color: Color(0xFFD04E4E),
                                  size: 16,
                                ),
                                label: const Text(
                                  "Обновить местоположение",
                                  style: TextStyle(
                                    color: Color(0xFFD04E4E),
                                    fontSize: 14,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 30),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Выбор способа оплаты
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D2D2D),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Способ оплаты",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildPaymentOption(
                                title: "Оплата по QR-коду",
                                subtitle: "СБП, Система быстрых платежей",
                                icon: Icons.qr_code,
                                value: "qr",
                                groupValue: _selectedPaymentMethod,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedPaymentMethod = value!;
                                    _validateForm(setState);
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildPaymentOption(
                                title: "Оплата на месте",
                                subtitle: "Наличными или картой при получении",
                                icon: Icons.payments,
                                value: "cash",
                                groupValue: _selectedPaymentMethod,
                                onChanged: (value) {
                                  setState(() {
                                    _selectedPaymentMethod = value!;
                                    _validateForm(setState);
                                  });
                                },
                              ),
                              
                              // Анимированный блок с содержимым в зависимости от способа оплаты
                              const SizedBox(height: 16),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  transitionBuilder: (Widget child, Animation<double> animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SizeTransition(
                                        sizeFactor: animation,
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _selectedPaymentMethod == 'qr'
                                      ? _buildQrPaymentWidget(
                                          context: context,
                                          title: title,
                                          price: price,
                                          currency: currency,
                                          description: description,
                                          address: _currentAddress,
                                          additionalInfo: _additionalInfoController.text,
                                          paymentMethod: _selectedPaymentMethod,
                                          isEnabled: _isFormValid,
                                        )
                                      : _selectedPaymentMethod == 'cash'
                                          ? _buildCashPaymentWidget(
                                              context: context,
                                              title: title,
                                              price: price,
                                              currency: currency,
                                              description: description,
                                              address: _currentAddress,
                                              additionalInfo: _additionalInfoController.text,
                                              isEnabled: _isFormValid,
                                            )
                                          : const SizedBox.shrink(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Поле для ввода дополнительной информации
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2D2D2D),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Дополнительная информация",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _additionalInfoController,
                                style: const TextStyle(color: Colors.white),
                                maxLines: 3,
                                decoration: InputDecoration(
                                  hintText: 'Введите дополнительную информацию...',
                                  hintStyle: TextStyle(color: Colors.grey[600]),
                                  filled: true,
                                  fillColor: const Color(0xFF1E1E1E),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (_) {
                                  _validateForm(setState);
                                },
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  // Виджет для оплаты наличными
  Widget _buildCashPaymentWidget({
    required BuildContext context,
    required String title,
    required double price,
    required String currency,
    required String description,
    required String address,
    String? additionalInfo,
    required bool isEnabled,
  }) {
    return Container(
      key: const ValueKey('cash-payment'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFD04E4E).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.payments_outlined,
            color: Colors.white,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            "Оплата при получении",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            "Вы сможете оплатить заказ наличными или картой при получении",
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: isEnabled 
                ? () async {
                    // Показываем индикатор загрузки
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (BuildContext context) {
                        return const AlertDialog(
                          backgroundColor: Color(0xFF2D2D2D),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                color: Color(0xFFD04E4E),
                              ),
                              SizedBox(height: 16),
                              Text(
                                "Оформление заказа...",
                                style: TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                    
                    // Сохраняем заказ с оплатой на месте
                    final success = await _saveOrder(
                      title: title,
                      price: price,
                      currency: currency,
                      description: description,
                      address: address,
                      additionalInfo: additionalInfo ?? '',
                      paymentMethod: 'cash',
                    );
                    
                    // Закрываем диалог загрузки
                    Navigator.of(context).pop();
                    
                    // Закрываем форму заказа
                    Navigator.of(context).pop();
                    
                    // Показываем сообщение об успехе или ошибке
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success 
                              ? 'Заказ успешно оформлен! Ожидайте звонка оператора.' 
                              : 'Ошибка при оформлении заказа',
                        ),
                        backgroundColor: success ? Colors.green : Colors.red,
                      ),
                    );
                  } 
                : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: isEnabled ? const Color(0xFFD04E4E) : Colors.grey,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "Оформить заказ",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          if (!isEnabled) ...[
            const SizedBox(height: 8),
            const Text(
              "Для продолжения заполните все обязательные поля",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  // Метод для отображения QR-кода
  Widget _buildQrPaymentWidget({
    required BuildContext context,
    required String title,
    required double price,
    required String currency,
    required String description,
    required String address,
    String? additionalInfo,
    required String paymentMethod,
    required bool isEnabled,
  }) {
    // Генерируем временный ID заказа для демонстрации
    final String tempOrderId = 'ORDER-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}';
    // Создаем URL для оплаты с параметром auto=true для автоматического подтверждения
    final String paymentUrl = _generatePaymentUrl(tempOrderId, price, paymentMethod) + '&auto=true';
    
    return Container(
      key: const ValueKey('qr-code'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFD04E4E).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          const Text(
            "Оплата по QR-коду",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          
          // Контейнер с информацией и кнопкой вместо QR-кода
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.qr_code_2,
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Для оплаты через СБП нажмите на кнопку ниже",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: isEnabled 
                      ? () async {
                          try {
                            print('Нажата кнопка "Перейти к оплате"');
                            
                            // Показываем диалог с индикатором загрузки
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (context) => AlertDialog(
                                backgroundColor: const Color(0xFF2D2D2D),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                title: const Text(
                                  "Оформление заказа",
                                  style: TextStyle(color: Colors.white),
                                ),
                                content: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(
                                      color: Color(0xFFD04E4E),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      "Создаем заказ и переходим к оплате...",
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            
                            // Сохраняем заказ - ВНИМАНИЕ: Здесь тип paymentMethod должен быть точно "qr"
                            print('Передаваемый метод оплаты: "$paymentMethod"');
                            
                            String? createdOrderId;
                            final success = await _saveOrder(
                              title: title,
                              price: price,
                              currency: currency,
                              description: description,
                              address: address,
                              additionalInfo: additionalInfo ?? '',
                              paymentMethod: 'qr', // Задаем явно "qr" вместо paymentMethod
                              onOrderCreated: (orderId) {
                                // Сохраняем ID созданного заказа
                                createdOrderId = orderId;
                                print('Создан заказ с ID: $orderId');
                              },
                            );
                            
                            if (!success) {
                              // Если не удалось создать заказ, показываем ошибку
                              Navigator.of(context).pop(); // Закрываем диалог загрузки
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Ошибка при создании заказа"),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            
                            // Дополнительная проверка статуса заказа после создания
                            if (createdOrderId != null) {
                              try {
                                final orderDoc = await FirebaseFirestore.instance
                                    .collection('orders')
                                    .doc(createdOrderId)
                                    .get();
                                
                                if (orderDoc.exists) {
                                  final orderData = orderDoc.data();
                                  print('Проверка статуса после создания заказа: ${orderData?['paymentStatus']}');
                                  
                                  // Если статус все еще "не оплачен", исправляем его
                                  if (orderData?['paymentStatus'] == 'не оплачен') {
                                    print('Статус заказа неверный, исправляем на "оплачен"');
                                    await FirebaseFirestore.instance
                                        .collection('orders')
                                        .doc(createdOrderId)
                                        .update({
                                          'paymentStatus': 'оплачен',
                                          'paidAt': FieldValue.serverTimestamp(),
                                        });
                                  }
                                }
                              } catch (e) {
                                print('Ошибка при проверке статуса заказа: $e');
                              }
                            }
                            
                            // Закрываем диалог загрузки
                            Navigator.of(context).pop();
                            
                            // Имитируем задержку перехода
                            await Future.delayed(const Duration(milliseconds: 500));
                            
                            // Открываем URL в браузере с помощью встроенного метода Flutter
                            final Uri url = Uri.parse(paymentUrl);
                            await _launchUrl(url);
                            
                            // Закрываем форму заказа
                            Navigator.of(context).pop();
                            
                            // Показываем уведомление об успешном оформлении заказа
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Заказ успешно оплачен и оформлен!"),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            print("Ошибка при открытии URL: $e");
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text("Ошибка при переходе к оплате: $e"),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } 
                      : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isEnabled ? const Color(0xFFD04E4E) : Colors.grey,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          "Перейти к оплате",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!isEnabled) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.info_outline, 
                            color: Colors.white, 
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (!isEnabled) ...[
                  const SizedBox(height: 8),
                  const Text(
                    "Для продолжения заполните все обязательные поля",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          const Text(
            "После оплаты заказ будет автоматически оформлен",
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.grey[400],
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  "ID заказа: $tempOrderId",
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Метод для обновления статуса оплаты заказа
  Future<void> _updateOrderPaymentStatus(String orderId) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
        'paymentStatus': 'оплачен',
        'paidAt': FieldValue.serverTimestamp(),
      });
      print('Статус оплаты заказа $orderId обновлен на: оплачен');
    } catch (e) {
      print('Ошибка при обновлении статуса оплаты заказа: $e');
    }
  }

  // Метод для открытия URL
  Future<void> _launchUrl(Uri url) async {
    try {
      // Метод для открытия URL без использования пакетов
      final canLaunch = await canLaunchUrl(url);
      if (canLaunch) {
        await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );
      } else {
        throw 'Не удалось открыть URL: $url';
      }
    } catch (e) {
      print('Ошибка при открытии URL: $e');
      // Показываем ошибку пользователю
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось открыть страницу оплаты'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Сохранение заказа в Firestore
  Future<bool> _saveOrder({
    required String title,
    required double price,
    required String currency,
    required String description,
    required String address,
    String? additionalInfo,
    required String paymentMethod,
    Function(String)? onOrderCreated,
  }) async {
    try {
      // Получаем текущего пользователя
      final user = AuthService().currentUser;
      
      if (user == null) {
        print('Ошибка: Пользователь не авторизован');
        return false;
      }

      // Определяем начальный статус оплаты в зависимости от метода
      // Для QR платежей сразу ставим статус "оплачен"
      String paymentStatus = 'не оплачен'; // Временная переменная
      
      // Явно сравниваем с конкретными строками с учетом регистра
      if (paymentMethod.trim().toLowerCase() == 'cash') {
        paymentStatus = 'ожидает оплаты';
      } else if (paymentMethod.trim().toLowerCase() == 'qr') {
        paymentStatus = 'оплачен';
      } else {
        paymentStatus = 'не оплачен';
      }
      
      print('Метод оплаты: "$paymentMethod", выбранный статус: "$paymentStatus"');
      
      // Текущая дата для поля paidAt, если оплачено через QR
      FieldValue? paidAt = paymentStatus == 'оплачен' ? FieldValue.serverTimestamp() : null;
      
      // Создаем новый заказ
      DocumentReference orderRef = await FirebaseFirestore.instance.collection('orders').add({
        'userId': user.uid,
        'userName': _userNameController.text,
        'userEmail': _userEmailController.text,
        'userPhone': _userPhoneController.text,
        'title': title,
        'price': price,
        'currency': currency,
        'description': description,
        'address': address,
        'additionalInfo': additionalInfo ?? '',
        'paymentMethod': paymentMethod,
        'paymentStatus': paymentStatus,
        'status': 'в обработке',
        'createdAt': FieldValue.serverTimestamp(),
        'paidAt': paidAt, // Добавляем время оплаты, если оплачено через QR
        'coordinates': _currentPosition != null ? 
          GeoPoint(_currentPosition!.latitude, _currentPosition!.longitude) : null,
        'arrivalCode': _generateConfirmationCode(), // Код подтверждения прибытия
        'completionCode': _generateConfirmationCode(), // Код подтверждения выполнения
      });
      
      print('Заказ создан с ID: ${orderRef.id} и статусом оплаты: "$paymentStatus"');
      
      // Вызываем колбэк с ID созданного заказа, если он передан
      if (onOrderCreated != null) {
        onOrderCreated(orderRef.id);
      }
      
      // Проверяем, что статус оплаты был успешно установлен
      try {
        final orderDoc = await FirebaseFirestore.instance
            .collection('orders')
            .doc(orderRef.id)
            .get();
        
        if (orderDoc.exists) {
          final orderData = orderDoc.data();
          final actualStatus = orderData?['paymentStatus'];
          print('Проверка статуса после сохранения заказа: "${actualStatus}"');
          
          if (actualStatus != paymentStatus) {
            print('ВНИМАНИЕ: Статус оплаты в базе данных отличается от ожидаемого');
            
            // Исправляем статус, если он не совпадает с ожидаемым для QR
            if (paymentMethod.trim().toLowerCase() == 'qr' && actualStatus != 'оплачен') {
              print('Исправляем статус заказа на "оплачен"');
              await orderRef.update({
                'paymentStatus': 'оплачен',
                'paidAt': FieldValue.serverTimestamp(),
              });
            }
          }
        }
      } catch (e) {
        print('Ошибка при проверке статуса заказа после сохранения: $e');
      }
      
      // Сохраняем данные пользователя если их еще нет
      try {
        final userDocRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
        final userDoc = await userDocRef.get();
        
        if (!userDoc.exists) {
          // Создаем документ пользователя
          await userDocRef.set({
            'displayName': _userNameController.text,
            'email': _userEmailController.text,
            'phone': _userPhoneController.text,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Обновляем только если данные изменились
          Map<String, dynamic> userData = {};
          
          final existingData = userDoc.data() ?? {};
          
          if (_userNameController.text.isNotEmpty && existingData['displayName'] != _userNameController.text) {
            userData['displayName'] = _userNameController.text;
          }
          
          if (_userPhoneController.text.isNotEmpty && existingData['phone'] != _userPhoneController.text) {
            userData['phone'] = _userPhoneController.text;
          }
          
          if (userData.isNotEmpty) {
            await userDocRef.update(userData);
          }
        }
      } catch (e) {
        print('Ошибка при сохранении данных пользователя: $e');
        // Но не прерываем выполнение, так как основная задача - сохранение заказа
      }
      
      return true;
    } catch (e) {
      print('Ошибка при сохранении заказа: $e');
      return false;
    }
  }

  // Метод для загрузки данных из Firestore
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      print('Загрузка данных из Firestore...');
      
      // Загрузка категорий из Firestore
      final categoriesSnapshot = await FirebaseFirestore.instance
          .collection('service_categories')
          .orderBy('order')
          .get();
      
      // Преобразование данных категорий
      final List<Map<String, dynamic>> categories = categoriesSnapshot.docs.map((doc) {
        return {
          'id': doc.id,
          'name': doc.data()['name'] ?? 'Без названия',
          'order': doc.data()['order'] ?? 0,
        };
      }).toList();
      
      print('Загружено ${categories.length} категорий');
      
      // Загрузка услуг из Firestore
      final servicesSnapshot = await FirebaseFirestore.instance
          .collection('services')
          .get();
      
      // Преобразование данных услуг
      final List<Map<String, dynamic>> services = servicesSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'title': data['title'] ?? 'Без названия',
          'price': data['price'] ?? 0,
          'currency': data['currency'] ?? '₽',
          'discount': data['discount'] ?? 0,
          'image': 'lib/assets/image 10.png', // Временно используем локальное изображение
          'description': data['description'] ?? 'Нет описания',
          'features': data['features'] ?? <String>[],
          'categoryId': data['categoryId'] ?? '',
        };
      }).toList();
      
      print('Загружено ${services.length} услуг');
      
      if (mounted) {
        setState(() {
          if (categories.isNotEmpty) {
            _categoryList = categories;
            // Извлекаем только названия категорий для отображения в UI
            _categories = categories.map((cat) => cat['name'] as String).toList();
          }
          
          if (services.isNotEmpty) {
            _services = services;
            _filteredServices = _filterByCategory(services);
          }
          
          _isLoading = false;
        });
        
        // Запускаем анимацию появления карточек
        _startAppearAnimation();
      }
    } catch (e) {
      print('Ошибка при загрузке данных из Firestore: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Метод для генерации URL для оплаты
  String _generatePaymentUrl(String orderId, double amount, String paymentMethod) {
    // URL вашего хостинга Firebase с параметрами заказа
    // Используем Firebase Hosting на x-gidrant.web.app
    String baseUrl = 'https://x-gidrant.web.app/payment.html';
    String returnUrl = 'x-gidrant://payment_success';
    
    // Формируем URL с параметрами
    String url = '$baseUrl?order_id=$orderId&amount=${amount.toInt()}&method=$paymentMethod&return_url=$returnUrl';
    
    return url;
  }

  Widget _buildPaymentOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    required String groupValue,
    required ValueChanged<String?>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: value == groupValue 
              ? const Color(0xFFD04E4E) 
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: RadioListTile<String>(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
          ),
        ),
        secondary: Icon(
          icon,
          color: value == groupValue 
              ? const Color(0xFFD04E4E) 
              : Colors.grey,
          size: 24,
        ),
        value: value,
        groupValue: groupValue,
        onChanged: onChanged,
        activeColor: const Color(0xFFD04E4E),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        dense: true,
        selectedTileColor: Colors.transparent,
      ),
    );
  }

  // Метод для отображения формы ввода данных карты
  Widget _buildCardPaymentForm({Function? onChanged}) {
    return Container(
      key: const ValueKey('card-form'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFD04E4E).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Данные карты",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _cardNumberController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Номер карты',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: const Color(0xFF2D2D2D),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(
                Icons.credit_card,
                color: Colors.grey,
              ),
            ),
            keyboardType: TextInputType.number,
            onChanged: (_) {
              if (onChanged != null) {
                onChanged();
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Поле для срока действия карты
              Expanded(
                child: TextField(
                  controller: _cardExpiryController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'ММ/ГГ',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: const Color(0xFF2D2D2D),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) {
                    if (onChanged != null) {
                      onChanged();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Поле для CVC/CVV
              Expanded(
                child: TextField(
                  controller: _cardCvcController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'CVC/CVV',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: const Color(0xFF2D2D2D),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  onChanged: (_) {
                    if (onChanged != null) {
                      onChanged();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cardHolderController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Имя владельца карты',
              hintStyle: TextStyle(color: Colors.grey[600]),
              filled: true,
              fillColor: const Color(0xFF2D2D2D),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) {
              if (onChanged != null) {
                onChanged();
              }
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Заменяем изображения на иконки
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.blue[900],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  "VISA",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  "MC",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  "МИР",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Получение текущего местоположения пользователя
  Future<bool> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });
    
    try {
      // Проверяем, включены ли службы геолокации
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Если службы геолокации отключены, показываем диалог с предложением включить
        setState(() {
          _currentAddress = 'Службы геолокации отключены';
          _isLoadingLocation = false;
        });
        
        showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Геолокация отключена', style: TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF2D2D2D),
            content: const Text(
              'Для определения вашего адреса необходимо включить службы геолокации.',
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Geolocator.openLocationSettings();
                },
                child: const Text('Открыть настройки', style: TextStyle(color: Color(0xFFD04E4E))),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        );
        
        return false;
      }

      // Проверяем разрешения на доступ к местоположению
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Если разрешения нет, запрашиваем его
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // Если разрешение не получено, показываем диалог
          setState(() {
            _currentAddress = 'Нет разрешения на доступ к местоположению';
            _isLoadingLocation = false;
          });
          
          showDialog(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: const Text('Разрешение отклонено', style: TextStyle(color: Colors.white)),
              backgroundColor: const Color(0xFF2D2D2D),
              content: const Text(
                'Для определения вашего адреса необходимо разрешение на доступ к местоположению.',
                style: TextStyle(color: Colors.white),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Понятно', style: TextStyle(color: Color(0xFFD04E4E))),
                ),
              ],
            ),
          );
          
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        // Если разрешение запрещено навсегда, показываем диалог с инструкциями
        setState(() {
          _currentAddress = 'Разрешение на доступ к местоположению запрещено навсегда';
          _isLoadingLocation = false;
        });
        
        showDialog(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Разрешение заблокировано', style: TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFF2D2D2D),
            content: const Text(
              'Для определения вашего адреса необходимо разрешение на доступ к местоположению. Пожалуйста, разрешите доступ в настройках устройства.',
              style: TextStyle(color: Colors.white),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Geolocator.openAppSettings();
                },
                child: const Text('Открыть настройки', style: TextStyle(color: Color(0xFFD04E4E))),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Закрыть', style: TextStyle(color: Colors.grey)),
              ),
            ],
          ),
        );
        
        return false;
      }

      // Получаем текущее местоположение
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      // Получаем адрес по координатам
      await _getAddressFromLatLng();
      
      setState(() {
        _isLoadingLocation = false;
      });
      return true;
      
    } catch (e) {
      print('Ошибка при получении местоположения: $e');
      setState(() {
        _currentAddress = 'Ошибка определения местоположения';
        _isLoadingLocation = false;
      });
      return false;
    }
  }
  
  // Получение адреса по координатам
  Future<void> _getAddressFromLatLng() async {
    try {
      if (_currentPosition != null) {
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          );
          
          if (placemarks.isNotEmpty) {
            Placemark place = placemarks[0];
            setState(() {
              _currentAddress = 
                  '${place.street}, ${place.subLocality}, ${place.locality}, ${place.administrativeArea}';
            });
          }
        } catch (e) {
          print('Ошибка при получении адреса: $e');
          // Используем координаты вместо адреса при ошибке геокодирования
          setState(() {
            _currentAddress = 'Координаты: ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}';
          });
        }
      }
    } catch (e) {
      print('Ошибка при получении адреса: $e');
      setState(() {
        _currentAddress = 'Ошибка определения адреса';
      });
    }
  }

  // Предварительное заполнение данных пользователя
  Future<void> _fillUserData() async {
    final authService = AuthService();
    final user = authService.currentUser;
    
    if (user != null) {
      _userEmailController.text = user.email ?? '';
      
      // Получаем дополнительные данные пользователя из Firestore
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists) {
          final userData = userDoc.data();
          setState(() {
            _userNameController.text = userData?['displayName'] ?? user.displayName ?? '';
            _userPhoneController.text = userData?['phone'] ?? '';
          });
        } else {
          _userNameController.text = user.displayName ?? '';
        }
      } catch (e) {
        print('Ошибка при получении данных пользователя: $e');
        _userNameController.text = user.displayName ?? '';
      }
    }
  }
} 