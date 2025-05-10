import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../auth/auth_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  bool _showOrderInfo = true; // Флаг для отображения информации о заказе
  final MapController _mapController = MapController();
  
  // Анимация пульсации маркера
  late AnimationController _pulseController;
  
  // Координаты центра Нижнего Новгорода (начальные значения)
  final LatLng _nizhnyNovgorod = const LatLng(56.3269, 44.0059);
  
  // Координаты текущего местоположения (будут обновлены при получении геолокации)
  LatLng _currentLocation = const LatLng(56.3168, 44.0088);
  
  // Флаг загрузки местоположения
  bool _isLoading = true;
  
  // Информация об активном заказе
  Map<String, dynamic>? _activeOrder;
  
  // Местоположение инженера
  LatLng? _engineerLocation;
  
  // Расчетное время прибытия
  String _estimatedArrivalTime = "Неизвестно";
  
  // Таймер для обновления данных заказа
  Timer? _orderUpdateTimer;
  
  @override
  void initState() {
    super.initState();
    
    // Инициализация контроллера анимации
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    // Запрашиваем геолокацию при создании экрана
    _getCurrentLocation();
    
    // Загружаем информацию об активном заказе
    _loadActiveOrder();
    
    // Устанавливаем таймер для обновления данных каждые 30 секунд
    _orderUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadActiveOrder();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _orderUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true; // Сохраняем состояние при переключении вкладок

  // Загружаем информацию об активном заказе пользователя
  Future<void> _loadActiveOrder() async {
    try {
      print('[КЛИЕНТ-КАРТА] Начинаем загрузку активного заказа...');
      final user = AuthService().currentUser;
      if (user == null) {
        print('[КЛИЕНТ-КАРТА] Пользователь не аутентифицирован');
        return;
      }
      print('[КЛИЕНТ-КАРТА] Текущий пользователь: \\${user.uid}');
      print('[КЛИЕНТ-КАРТА] Пытаемся получить заказы по полю clientId и userId для UID: \\${user.uid}');
      // Пробуем оба варианта фильтрации
      final snapshotClientId = await FirebaseFirestore.instance
          .collection('orders')
          .where('clientId', isEqualTo: user.uid)
          .where('status', whereIn: ['принят', 'выехал', 'прибыл', 'работает'])
          .get();
      final snapshotUserId = await FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: user.uid)
          .where('status', whereIn: ['принят', 'выехал', 'прибыл', 'работает'])
          .get();
      print('[КЛИЕНТ-КАРТА] Получено заказов по clientId: \\${snapshotClientId.docs.length}');
      print('[КЛИЕНТ-КАРТА] Получено заказов по userId: \\${snapshotUserId.docs.length}');
      if (snapshotClientId.docs.isNotEmpty) {
        print('[КЛИЕНТ-КАРТА] Используем заказ по clientId');
        final orderDoc = snapshotClientId.docs.first;
        final orderData = orderDoc.data();
        print('[КЛИЕНТ-КАРТА] Данные заказа (clientId): \\${orderData}');
        setState(() {
          _activeOrder = orderData;
          _showOrderInfo = true;
          print('[КЛИЕНТ-КАРТА] _activeOrder обновлён (clientId): \\${_activeOrder}');
          if (_activeOrder!['engineerLocationAtAccept'] != null) {
            print('[КЛИЕНТ-КАРТА] engineerLocationAtAccept найден: \\${_activeOrder!['engineerLocationAtAccept']}');
            _updateEngineerLocation(_activeOrder!['engineerLocationAtAccept']);
          } else {
            print('[КЛИЕНТ-КАРТА] Нет engineerLocationAtAccept');
          }
        });
      } else if (snapshotUserId.docs.isNotEmpty) {
        print('[КЛИЕНТ-КАРТА] Используем заказ по userId');
        final orderDoc = snapshotUserId.docs.first;
        final orderData = orderDoc.data();
        print('[КЛИЕНТ-КАРТА] Данные заказа (userId): \\${orderData}');
        setState(() {
          _activeOrder = orderData;
          _showOrderInfo = true;
          print('[КЛИЕНТ-КАРТА] _activeOrder обновлён (userId): \\${_activeOrder}');
          if (_activeOrder!['engineerLocationAtAccept'] != null) {
            print('[КЛИЕНТ-КАРТА] engineerLocationAtAccept найден: \\${_activeOrder!['engineerLocationAtAccept']}');
            _updateEngineerLocation(_activeOrder!['engineerLocationAtAccept']);
          } else {
            print('[КЛИЕНТ-КАРТА] Нет engineerLocationAtAccept');
          }
        });
      } else {
        print('[КЛИЕНТ-КАРТА] Активные заказы не найдены ни по clientId, ни по userId');
        setState(() {
          _activeOrder = null;
          _engineerLocation = null;
          _estimatedArrivalTime = "Неизвестно";
        });
      }
    } catch (e) {
      print('[КЛИЕНТ-КАРТА] ОШИБКА при загрузке активного заказа: \\${e}');
      print(StackTrace.current);
    }
  }
  
  // Обновляем местоположение инженера и рассчитываем примерное время прибытия
  void _updateEngineerLocation(Map<String, dynamic> locationData) {
    print('[КЛИЕНТ-КАРТА] Обработка данных о местоположении инженера: $locationData');
    
    try {
      if (locationData['latitude'] != null && locationData['longitude'] != null) {
        // Проверяем типы данных
        print('[КЛИЕНТ-КАРТА] Типы данных: lat=${locationData['latitude'].runtimeType}, lng=${locationData['longitude'].runtimeType}');
        
        // Явно приводим к типу double для гарантии совместимости
        double lat = 0.0;
        double lng = 0.0;
        
        // Преобразуем значения в зависимости от того, в каком виде они пришли
        if (locationData['latitude'] is double) {
          lat = locationData['latitude'];
        } else if (locationData['latitude'] is int) {
          lat = (locationData['latitude'] as int).toDouble();
        } else {
          lat = double.tryParse(locationData['latitude'].toString()) ?? 0.0;
        }
        
        if (locationData['longitude'] is double) {
          lng = locationData['longitude'];
        } else if (locationData['longitude'] is int) {
          lng = (locationData['longitude'] as int).toDouble();
        } else {
          lng = double.tryParse(locationData['longitude'].toString()) ?? 0.0;
        }
        
        print('[КЛИЕНТ-КАРТА] Преобразованные координаты инженера: $lat, $lng');
        
        _engineerLocation = LatLng(lat, lng);
        
        // Рассчитываем примерное время прибытия
        _calculateEstimatedArrivalTime();
        
        // Обновляем карту, чтобы показать обе точки
        _centerMapOnPoints();
        
        print('[КЛИЕНТ-КАРТА] Местоположение инженера успешно обновлено');
      } else {
        print('[КЛИЕНТ-КАРТА] ОШИБКА: Данные о местоположении отсутствуют или null');
        print('[КЛИЕНТ-КАРТА] Полученные данные: $locationData');
      }
    } catch (e) {
      print('[КЛИЕНТ-КАРТА] КРИТИЧЕСКАЯ ОШИБКА при обработке местоположения инженера: $e');
      print(StackTrace.current);
    }
  }
  
  // Центрируем карту так, чтобы оба маркера были видны
  void _centerMapOnPoints() {
    if (_engineerLocation != null) {
      // Задержка, чтобы убедиться, что карта инициализирована
      Future.delayed(Duration(milliseconds: 100), () {
        try {
          print('[КЛИЕНТ-КАРТА] Центрирование карты для отображения обоих маркеров');
          // Находим средние координаты между пользователем и инженером
          final centerLat = (_currentLocation.latitude + _engineerLocation!.latitude) / 2;
          final centerLng = (_currentLocation.longitude + _engineerLocation!.longitude) / 2;
          
          // Вычисляем расстояние между точками для определения оптимального зума
          final distance = Geolocator.distanceBetween(
            _currentLocation.latitude, 
            _currentLocation.longitude,
            _engineerLocation!.latitude,
            _engineerLocation!.longitude
          );
          
          print('[КЛИЕНТ-КАРТА] Расстояние между точками: $distance м');
          
          // Выбираем зум в зависимости от расстояния
          double zoom = 15.0;
          if (distance > 10000) zoom = 10.0;
          else if (distance > 5000) zoom = 11.0;
          else if (distance > 2000) zoom = 12.0;
          else if (distance > 1000) zoom = 13.0;
          else if (distance > 500) zoom = 14.0;
          
          print('[КЛИЕНТ-КАРТА] Выбран масштаб карты: $zoom');
          
          // Перемещаем карту на новый центр с рассчитанным зумом
          _mapController.move(LatLng(centerLat, centerLng), zoom);
          print('[КЛИЕНТ-КАРТА] Карта успешно центрирована');
        } catch (e) {
          print('[КЛИЕНТ-КАРТА] ОШИБКА при центрировании карты: $e');
          print(StackTrace.current);
        }
      });
    } else {
      print('[КЛИЕНТ-КАРТА] Невозможно центрировать карту: местоположение инженера не определено');
    }
  }
  
  // Рассчитываем примерное время прибытия инженера
  void _calculateEstimatedArrivalTime() {
    if (_engineerLocation == null) {
      print('[КЛИЕНТ-КАРТА] Невозможно рассчитать время прибытия: местоположение инженера не определено');
      _estimatedArrivalTime = "Неизвестно";
      return;
    }
    
    try {
      print('[КЛИЕНТ-КАРТА] Расчёт примерного времени прибытия');
      // Рассчитываем расстояние в метрах
      final distance = Geolocator.distanceBetween(
        _currentLocation.latitude, 
        _currentLocation.longitude,
        _engineerLocation!.latitude,
        _engineerLocation!.longitude
      );
      
      print('[КЛИЕНТ-КАРТА] Расстояние до инженера: $distance м');
      
      // Предполагаем среднюю скорость 40 км/ч в городе
      const averageSpeedKmh = 40.0;
      
      // Преобразуем км/ч в м/с: 40 km/h = 40000 m / 3600 s = 11.11 m/s
      const averageSpeedMs = averageSpeedKmh * 1000 / 3600;
      
      // Рассчитываем время в секундах
      final timeInSeconds = distance / averageSpeedMs;
      
      print('[КЛИЕНТ-КАРТА] Расчетное время в пути: ${timeInSeconds.round()} с');
      
      // Преобразуем секунды в минуты и часы для отображения
      if (timeInSeconds < 60) {
        _estimatedArrivalTime = "Меньше минуты";
      } else if (timeInSeconds < 3600) {
        final minutes = (timeInSeconds / 60).round();
        _estimatedArrivalTime = "$minutes ${_pluralize(minutes, 'минута', 'минуты', 'минут')}";
      } else {
        final hours = (timeInSeconds / 3600).floor();
        final minutes = ((timeInSeconds % 3600) / 60).round();
        
        if (minutes == 0) {
          _estimatedArrivalTime = "$hours ${_pluralize(hours, 'час', 'часа', 'часов')}";
        } else {
          _estimatedArrivalTime = "$hours ${_pluralize(hours, 'час', 'часа', 'часов')} $minutes ${_pluralize(minutes, 'минута', 'минуты', 'минут')}";
        }
      }
      
      print('[КЛИЕНТ-КАРТА] Расчетное время прибытия: $_estimatedArrivalTime');
    } catch (e) {
      print('[КЛИЕНТ-КАРТА] ОШИБКА при расчете времени прибытия: $e');
      print(StackTrace.current);
      _estimatedArrivalTime = "Неизвестно";
    }
  }
  
  // Вспомогательная функция для правильного склонения слов
  String _pluralize(int count, String one, String few, String many) {
    if (count % 10 == 1 && count % 100 != 11) {
      return one;
    } else if ([2, 3, 4].contains(count % 10) && ![12, 13, 14].contains(count % 100)) {
      return few;
    } else {
      return many;
    }
  }

  // Метод для запроса разрешений и получения текущего местоположения
  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Проверяем, включены ли службы геолокации
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Службы геолокации отключены, показываем уведомление
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Службы геолокации отключены. Пожалуйста, включите их для определения вашего местоположения.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // Проверяем разрешения на доступ к геолокации
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Разрешение отклонено, показываем уведомление
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Разрешение на доступ к геолокации отклонено.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Разрешение отклонено навсегда, показываем уведомление
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Разрешение на доступ к геолокации отклонено навсегда. Пожалуйста, измените настройки в приложении.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // Получаем текущее местоположение
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      if (mounted) {
        setState(() {
          // Обновляем координаты текущего местоположения
          _currentLocation = LatLng(position.latitude, position.longitude);
          _isLoading = false;
          
          // Перемещаем карту на текущее местоположение
          _mapController.move(_currentLocation, 15);
        });
      }
    } catch (e) {
      // Обработка ошибок при получении местоположения
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при получении местоположения: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Необходимо для AutomaticKeepAliveClientMixin
    
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Scaffold(
      body: Stack(
        children: [
          // Основная карта
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 13.0,
              maxZoom: 18.0,
              minZoom: 4.0,
            ),
            children: [
              // Слой карты
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.company.xgidrant',
                tileProvider: NetworkTileProvider(),
              ),
              
              // Маркеры на карте
              MarkerLayer(
                markers: [
                  // Пульсирующий маркер текущего местоположения пользователя
                  Marker(
                    point: _currentLocation,
                    alignment: Alignment.center,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final pulseValue = (1.0 + 0.2 * _pulseController.value) % 1.2;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: 1 - _pulseController.value,
                              child: Transform.scale(
                                scale: pulseValue * 1.5,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF44336).withOpacity(0.3),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF44336),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  
                  // Маркер местоположения инженера (если доступен)
                  if (_engineerLocation != null)
                    Marker(
                      point: _engineerLocation!,
                      alignment: Alignment.center,
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final pulseValue = (1.0 + 0.2 * _pulseController.value) % 1.2;
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              Opacity(
                                opacity: 1 - _pulseController.value,
                                child: Transform.scale(
                                  scale: pulseValue * 1.5,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4CAF50).withOpacity(0.3),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
          
          // Подпись "Вы здесь" в углу карты вместо маркера
          if (!_isLoading)
            Positioned(
              left: 16,
              top: statusBarHeight + ((_showOrderInfo) ? 70 : 16),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF44336),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Вы здесь',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Подпись "Ваш инженер" для местоположения инженера
          if (_engineerLocation != null)
            Positioned(
              left: 16,
              top: statusBarHeight + ((_showOrderInfo) ? 110 : 56),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Ваш инженер',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Индикатор загрузки местоположения
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD04E4E)),
              ),
            ),
          
          // Верхний баннер "Активный заказ" или "Нет активных заказов"
          if (_showOrderInfo)
            Positioned(
              top: statusBarHeight + 16,
              left: 16,
              right: 16,
              child: Material(
                color: _activeOrder != null ? Colors.black87 : Colors.black54,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _activeOrder != null 
                              ? 'Ваш инженер прибудет через: $_estimatedArrivalTime' 
                              : 'Нет активных заказов',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showOrderInfo = false;
                          });
                        },
                        child: const Icon(
                          Icons.close,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          
          // Кнопки управления картой (увеличение, уменьшение, моё местоположение)
          Positioned(
            right: 16,
            bottom: bottomPadding + 80, // Учитываем отступ и размер навигационной панели
            child: Column(
              children: [
                _buildMapButton(
                  icon: Icons.add,
                  onPressed: () {
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(_mapController.camera.center, currentZoom + 1);
                  },
                ),
                const SizedBox(height: 8),
                _buildMapButton(
                  icon: Icons.remove,
                  onPressed: () {
                    final currentZoom = _mapController.camera.zoom;
                    _mapController.move(_mapController.camera.center, currentZoom - 1);
                  },
                ),
                const SizedBox(height: 8),
                _buildMapButton(
                  icon: Icons.my_location,
                  onPressed: () {
                    _mapController.move(_currentLocation, 15);
                    
                    // Если местоположение не определено, запрашиваем его
                    if (_isLoading) {
                      _getCurrentLocation();
                    }
                  },
                ),
                if (_engineerLocation != null) ...[
                  const SizedBox(height: 8),
                  _buildMapButton(
                    icon: Icons.engineering,
                    onPressed: () {
                      _mapController.move(_engineerLocation!, 15);
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildMapButton(
                    icon: Icons.center_focus_weak,
                    onPressed: () {
                      _centerMapOnPoints();
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMapButton({required IconData icon, required VoidCallback onPressed}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: Icon(
              icon,
              color: Colors.black87,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
} 