import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Индекс выбранной категории
  int _selectedCategoryIndex = 0;
  
  // Список категорий услуг
  final List<String> _categories = [
    'Монтаж',
    'Демонтаж',
    'Обслуживание',
  ];

  // Список услуг (моковые данные)
  final List<Map<String, dynamic>> _services = [
    {
      'title': 'Демонтаж гидрантов',
      'price': 1299,
      'discount': 21,
      'currency': '\$',
      'image': 'lib/assets/image 10.png',
    },
    {
      'title': 'Демонтаж гидрантов',
      'price': 1299,
      'currency': '\$',
      'image': 'lib/assets/image 10.png',
    },
    {
      'title': 'Демонтаж гидрантов',
      'price': 1299,
      'currency': '\$',
      'image': 'lib/assets/image 10.png',
    },
    {
      'title': 'Демонтаж гидрантов',
      'price': 1299,
      'currency': '\$',
      'image': 'lib/assets/image 10.png',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Поиск
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Row(
                    children: [
                      // Поле поиска
                      Expanded(
                        child: Container(
                          color: const Color(0xFF1E1E1E),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Icon(Icons.search, color: Colors.white, size: 24),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  style: const TextStyle(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'Найти услугу',
                                    hintStyle: TextStyle(color: Colors.grey[400]),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Кнопка поиска
                      Container(
                        width: 100,
                        color: const Color(0xFFD04E4E),
                        child: const Center(
                          child: Text(
                            'Поиск',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Категории услуг (скроллируемые горизонтально)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(_categories.length, (index) {
                    final isSelected = _selectedCategoryIndex == index;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategoryIndex = index;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          _categories[index],
                          style: TextStyle(
                            color: isSelected ? const Color(0xFFD04E4E) : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Список услуг (сетка)
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.58,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _services.length,
                itemBuilder: (context, index) {
                  final service = _services[index];
                  return _buildServiceCard(
                    title: service['title'],
                    price: (service['price'] as int).toDouble(),
                    currency: service['currency'],
                    discount: service['discount'],
                    image: service['image'],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildServiceCard({
    required String title,
    required double price,
    required String currency,
    int? discount,
    required String image,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          // Карточка со сниженной высотой, чтобы кнопка "Заказать" выступала вниз
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Изображение услуги
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  child: Image.asset(
                    image,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              
              // Информация об услуге
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            "${price.toInt()}$currency",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                      const SizedBox(height: 30), // Уменьшено пространство для кнопки
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          // Скидка (если есть)
          if (discount != null)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFD04E4E),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "-$discount%",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          
          // Кнопка заказать
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Container(
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFD04E4E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  "Заказать",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 