import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

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
  }

  @override
  bool get wantKeepAlive => true; // Сохраняем состояние при переключении вкладок

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
                  // Пульсирующий маркер текущего местоположения
                  Marker(
                    point: _currentLocation,
                    alignment: Alignment.center, // Центрируем маркер по точке на карте
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        // Создаем пульсирующий эффект
                        final pulseValue = (1.0 + 0.2 * _pulseController.value) % 1.2;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            // Внешний круг пульсации
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
                            // Основной маркер
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
          
          // Индикатор загрузки местоположения
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD04E4E)),
              ),
            ),
          
          // Верхний баннер "Нет активных заказов"
          if (_showOrderInfo)
            Positioned(
              top: statusBarHeight + 16,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Нет активных заказов',
                          style: TextStyle(
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
  
  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }
} 