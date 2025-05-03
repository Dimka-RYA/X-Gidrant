import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final AuthService _authService = AuthService();
  String? _userEmail;
  String _registrationDate = 'Не указано';
  int _ordersCount = 0;
  bool _isLoading = true;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // Загрузка данных пользователя из Firebase
  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    
    try {
      final user = _authService.currentUser;
      
      if (user != null) {
        if (!mounted) return;
        // Получаем время создания аккаунта
        final creationTime = user.metadata.creationTime;
        final formattedDate = creationTime != null 
            ? '${creationTime.day}.${creationTime.month}.${creationTime.year}'
            : 'Не указано';
        
        setState(() {
          _userEmail = user.email;
          _registrationDate = formattedDate;
        });
        
        // Проверяем, есть ли пользователь в базе
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        if (userDoc.exists) {
          final userData = userDoc.data();
          if (userData != null) {
            // Загружаем количество заказов, если оно есть
            final orders = userData['ordersCount'] ?? 0;
            
            if (!mounted) return;
            setState(() {
              _nameController.text = userData['name'] ?? '';
              _ordersCount = orders;
            });
          }
        }

        // Также получаем количество заказов из коллекции orders, если она существует
        try {
          final ordersSnapshot = await FirebaseFirestore.instance
              .collection('orders')
              .where('userId', isEqualTo: user.uid)
              .get();
              
          if (!mounted) return;
          setState(() {
            _ordersCount = ordersSnapshot.docs.length;
          });
        } catch (e) {
          print('Ошибка при загрузке заказов: $e');
        }
      }
    } catch (e) {
      print('Ошибка при загрузке данных пользователя: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Сохранение данных пользователя в Firebase
  Future<void> _saveUserData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _isEditing = false;
    });
    
    try {
      final user = _authService.currentUser;
      
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
              'name': _nameController.text.trim(),
              'email': _userEmail,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Имя успешно сохранено'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Ошибка при сохранении данных пользователя: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка при сохранении: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFD04E4E)))
            : Column(
              children: [
                const SizedBox(height: 20),
                
                // Иконки в шапке
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Иконка настроек SVG без серого фона
                    SvgPicture.asset(
                      'lib/assets/Frame.svg',
                      width: 30,
                      height: 30,
                    ),
                    // Иконка выхода без серого фона
                    IconButton(
                      icon: const Icon(Icons.logout, color: Color(0xFFD04E4E)),
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
                
                const SizedBox(height: 20),
                
                // Аватар пользователя
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 80,
                    color: Colors.grey,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Имя пользователя (редактируемое)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _isEditing 
                      ? Container(
                          margin: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD04E4E), width: 1),
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 5,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: Stack(
                            children: [
                              TextField(
                                controller: _nameController,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                cursorColor: const Color(0xFFD04E4E),
                                decoration: const InputDecoration(
                                  hintText: 'Введите ваше имя',
                                  hintStyle: TextStyle(
                                    fontSize: 20,
                                    color: Colors.grey,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 10,
                                top: 0,
                                bottom: 0,
                                child: Center(
                                  child: IconButton(
                                    icon: const Icon(Icons.check_circle, color: Color(0xFFD04E4E), size: 28),
                                    onPressed: _saveUserData,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : GestureDetector(
                          onTap: () {
                            setState(() {
                              _isEditing = true;
                            });
                          },
                          child: Text(
                            _nameController.text.isEmpty 
                              ? 'Нажмите, чтобы ввести имя' 
                              : _nameController.text,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _nameController.text.isEmpty 
                                ? Colors.grey 
                                : Colors.black,
                            ),
                          ),
                        ),
                    ),
                  ],
                ),
                
                // Email пользователя
                Text(
                  _userEmail ?? 'Email не найден',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Карточки статистики
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        height: 102,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9D9D9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'Дата регистрации',
                              style: TextStyle(
                                color: Color(0xFF666666),
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _registrationDate,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF333333),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        height: 102,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9D9D9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text(
                              'Заказы',
                              style: TextStyle(
                                color: Color(0xFF666666),
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_ordersCount',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF333333),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 32),
                
                // Раздел отзывов
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Отзывы',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Отзыв 1
                _buildReviewCard(),
                
                const SizedBox(height: 12),
                
                // Отзыв 2
                _buildReviewCard(),
                
                const SizedBox(height: 20),
                
                // Кнопка выхода
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        await AuthService().signOut();
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(context, '/login');
                        }
                      } catch (e) {
                        print('Ошибка при выходе: $e');
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Ошибка при выходе: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Выйти из аккаунта',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildReviewCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Вадим Романов',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.star, color: Colors.yellow, size: 14),
                      Icon(Icons.star, color: Colors.yellow, size: 14),
                      Icon(Icons.star, color: Colors.yellow, size: 14),
                      Icon(Icons.star, color: Colors.yellow, size: 14),
                      Icon(Icons.star, color: Colors.yellow, size: 14),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Всё сделано круто, буду заказывать еще. Всё сделано круто, буду заказывать еще...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
} 