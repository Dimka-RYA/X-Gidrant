import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/map_screen.dart';
import 'screens/history_screen.dart' as history;
import 'screens/profile_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 3; // Выбираем вкладку Профиль по умолчанию
  // PageController для управления свайпом страниц
  final PageController _pageController = PageController(
    initialPage: 3, // Устанавливаем начальную страницу "Профиль"
    keepPage: true,
    viewportFraction: 1.0,
  );
  
  // Список экранов для каждой вкладки
  final List<Widget> _screens = [
    const MapScreen(),
    const history.HistoryScreen(),
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
                  _buildNavItem(0, 'lib/assets/map1.svg', 'Карта'),
                  _buildNavItem(1, 'lib/assets/history.svg', 'История'),
                  _buildNavItem(2, 'lib/assets/home.svg', 'Главная'),
                  _buildNavItem(3, 'lib/assets/user.svg', 'Профиль'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNavItem(int index, String svgPath, String label) {
    final isSelected = _selectedIndex == index;
    final accentColor = const Color(0xFFD04E4E);
    final defaultColor = Colors.white;
    
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
      child: SizedBox(
        width: 75,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Иконка и текст - центрированы вертикально
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  svgPath,
                  width: 24,
                  height: 24,
                  colorFilter: ColorFilter.mode(
                    isSelected ? accentColor : defaultColor, 
                    BlendMode.srcIn,
                  ),
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
                    ? accentColor 
                    : Colors.transparent,
                  // Скругляем по половине высоты для плавных краев
                  // Скругляем только нижние углы, верхние остаются прямыми
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
}

// Кастомная физика для более плавного скроллинга между несмежными вкладками
class CustomPageViewScrollPhysics extends ScrollPhysics {
  const CustomPageViewScrollPhysics({super.parent});

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