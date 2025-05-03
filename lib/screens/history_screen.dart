import 'package:flutter/material.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'История заказов',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Фильтры
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildFilterButton('Все', true),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFilterButton('Активные', false),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFilterButton('Завершенные', false),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Список заказов
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 10,
                itemBuilder: (context, index) {
                  return _buildOrderCard(index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterButton(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.red : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? Colors.red : Colors.grey[300]!,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildOrderCard(int index) {
    // Статус заказа
    final bool isActive = index % 3 == 0;
    final String status = isActive ? 'В процессе' : 'Завершен';
    final Color statusColor = isActive ? Colors.blue : Colors.green;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      child: Column(
        children: [
          // Шапка карточки с номером и статусом
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Заказ #${1000 + index}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Содержимое карточки
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Услуга
                _buildInfoRow(
                  'Услуга:',
                  'Установка гидранта',
                ),
                const SizedBox(height: 8),
                
                // Адрес
                _buildInfoRow(
                  'Адрес:',
                  'ул. Ленина, 42, Москва',
                ),
                const SizedBox(height: 8),
                
                // Дата
                _buildInfoRow(
                  'Дата:',
                  '${10 + index}.05.2024',
                ),
                const SizedBox(height: 8),
                
                // Стоимость
                _buildInfoRow(
                  'Стоимость:',
                  '${5000 + index * 100} ₽',
                  valueStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Кнопки
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Детали'),
                      ),
                    ),
                    if (isActive) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Отменить'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {TextStyle? valueStyle}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: valueStyle ?? const TextStyle(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
} 