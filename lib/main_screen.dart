import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/history_screen.dart';
import 'screens/profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; // Выбираем вкладку по умолчанию
  // PageController для управления свайпом страниц
  final PageController _pageController = PageController(
    initialPage: 0,
    keepPage: true,
    viewportFraction: 1.0,
  );
  
  // Список экранов для каждой вкладки
  final List<Widget> _screens = [
    const MapScreen(),
    const HistoryScreen(),
    const HomeScreen(),
    const ProfileScreen(),
  ];

  @override
  void dispose() {
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
            physics: const CustomPageViewScrollPhysics(),
            pageSnapping: true,
            allowImplicitScrolling: true, // Кэширует соседние страницы для более плавного перехода
            padEnds: false, // Убираем отступы для более точного позиционирования
            onPageChanged: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            children: _screens,
          ),
          
          // Навигационная панель
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
                  _buildNavItem(0, Icons.menu_book, 'Карта'),
                  _buildNavItem(1, Icons.access_time, 'История'),
                  _buildNavItem(2, Icons.home_outlined, 'Главная'),
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
    
    return InkWell(
      onTap: () {
        // При переходе по нажатию меняем страницу с анимацией
        // Плавно переходим на нужную страницу без прохождения промежуточных
        setState(() {
          _selectedIndex = index;
        });
        // Используем animateToPage с оптимизированной анимацией
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuad,
        );
      },
      child: Container(
        width: 75,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Иконка и текст - центрированы вертикально
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    color: isSelected 
                      ? const Color(0xFFD04E4E) 
                      : Colors.white,
                  ),
                  child: Icon(
                    icon,
                    size: 24,
                    color: isSelected 
                      ? const Color(0xFFD04E4E) 
                      : Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    color: isSelected 
                      ? const Color(0xFFD04E4E) 
                      : Colors.white,
                    fontSize: 10,
                  ),
                  child: Text(label),
                ),
              ],
            ),
            
            // Красная полоска, утопленная наполовину вверх
            Positioned(
              top: 0,
              child: AnimatedContainer(
                height: 3,
                width: 40,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutQuad,
                decoration: BoxDecoration(
                  // Используем AnimatedContainer для плавной анимации индикатора
                  color: isSelected 
                    ? const Color(0xFFD04E4E) 
                    : Colors.transparent,
                  // Скругляем по половине высоты для плавных краев
                  // Скругляем только нижние углы, верхние остаются прямыми
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(3.5),
                    bottomRight: Radius.circular(3.5),
                  ),

                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: const Color(0xFFD04E4E).withOpacity(0.5),
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
}

// Кастомная физика для более плавного скроллинга между несмежными вкладками
class CustomPageViewScrollPhysics extends ScrollPhysics {
  const CustomPageViewScrollPhysics({ScrollPhysics? parent}) 
      : super(parent: parent);

  @override
  CustomPageViewScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return CustomPageViewScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 70, // Более стабильное значение массы
        stiffness: 100, // Умеренная жесткость
        damping: 1.0, // Стандартное демпфирование
      );
} 