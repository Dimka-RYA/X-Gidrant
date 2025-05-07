import 'package:flutter/material.dart';
import '../auth/auth_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';

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
  
  // Переменная для хранения изображения профиля
  File? _profileImage;
  // Ссылка на изображение профиля в Firestore
  String? _profileImageUrl;
  
  // Переменные для отображения всплывающего уведомления
  bool _showNotification = false;
  String _notificationMessage = '';
  Color _notificationColor = Colors.green;
  Timer? _notificationTimer;
  
  // Список отзывов пользователя
  List<Map<String, dynamic>> _reviews = [];
  // Флаг загрузки отзывов
  bool _isLoadingReviews = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserReviews();
  }

  @override
  void dispose() {
    _nameController.dispose();
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
  
  // Сохранение изображения в Firebase Storage и обновление профиля
  Future<void> _saveProfileImage() async {
    if (_profileImage == null) return;
    
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    
    try {
      final user = _authService.currentUser;
      
      if (user != null) {
        /* 
        // Код загрузки изображения в Firebase Storage
        // В этом примере мы только сохраняем путь к локальному файлу
        // В реальном приложении здесь должен быть код загрузки в Firebase Storage
        
        final storageRef = FirebaseStorage.instance.ref();
        final imageRef = storageRef.child('profile_images/${user.uid}.jpg');
        
        final uploadTask = imageRef.putFile(_profileImage!);
        final snapshot = await uploadTask.whenComplete(() => null);
        
        final downloadUrl = await snapshot.ref.getDownloadURL();
        */
        
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
            }, SetOptions(merge: true)); // merge: true позволяет обновить только указанные поля
            
        if (!mounted) return;
        setState(() {
          _profileImageUrl = localPath;
        });
        
        // Показываем всплывающее уведомление вместо Snackbar
        _showTopNotification('Изображение профиля обновлено');
      }
    } catch (e) {
      print('Ошибка при сохранении изображения профиля: $e');
      if (!mounted) return;
      _showTopNotification('Ошибка при сохранении изображения: $e', color: Colors.red);
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
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
            
            // Загружаем путь к изображению профиля, если оно есть
            final profileImagePath = userData['profileImagePath'];
            
            if (!mounted) return;
            setState(() {
              _nameController.text = userData['name'] ?? '';
              _ordersCount = orders;
              _profileImageUrl = profileImagePath;
              
              if (profileImagePath != null) {
                // Проверяем, существует ли файл
                final file = File(profileImagePath);
                if (file.existsSync()) {
                  _profileImage = file;
                }
              }
            });
          }
        } else {
          // Создаем документ для пользователя, если его не существует
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'uid': user.uid,
                'email': user.email ?? '',
                'name': 'Пользователь',
                'createdAt': FieldValue.serverTimestamp(),
              });
              
          if (!mounted) return;
          setState(() {
            _nameController.text = 'Пользователь';
          });
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
        // Используем set вместо update, чтобы создать документ, если его нет
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({
              'name': _nameController.text.trim(),
              'updatedAt': FieldValue.serverTimestamp(),
              'uid': user.uid, // Добавляем uid, чтобы документ точно содержал эти данные
              'email': user.email ?? '', // Добавляем email, если он доступен
            }, SetOptions(merge: true)); // merge: true позволяет обновить только указанные поля
            
        if (!mounted) return;
        _showTopNotification('Данные профиля успешно обновлены');
      }
    } catch (e) {
      print('Ошибка при сохранении данных пользователя: $e');
      if (!mounted) return;
      _showTopNotification('Ошибка при сохранении: $e', color: Colors.red);
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Метод для загрузки отзывов пользователя из Firestore
  Future<void> _loadUserReviews() async {
    if (!mounted) return;
    setState(() {
      _isLoadingReviews = true;
    });
    
    try {
      final user = _authService.currentUser;
      
      if (user != null) {
        // Получаем отзывы из коллекции reviews, где userId соответствует ID текущего пользователя
        final reviewsSnapshot = await FirebaseFirestore.instance
            .collection('reviews')
            .where('userId', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true) // Сортируем от новых к старым
            .get();
            
        if (!mounted) return;
        
        // Преобразуем документы в список Map
        final reviews = reviewsSnapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'id': doc.id,
            'authorName': data['authorName'] ?? 'Неизвестный пользователь',
            'authorId': data['authorId'] ?? '',
            'authorImageUrl': data['authorImageUrl'],
            'rating': data['rating'] ?? 5,
            'text': data['text'] ?? 'Нет текста отзыва',
            'createdAt': data['createdAt'] ?? Timestamp.now(),
          };
        }).toList();
        
        setState(() {
          _reviews = reviews;
          _isLoadingReviews = false;
        });
        
        print('Загружено ${_reviews.length} отзывов');
      }
    } catch (e) {
      print('Ошибка при загрузке отзывов: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingReviews = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
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
                    GestureDetector(
                      onTap: _pickImage, // Вызываем метод выбора изображения при нажатии
                      child: Stack(
                        children: [
                          // Аватар
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              shape: BoxShape.circle,
                              image: _profileImage != null
                                  ? DecorationImage(
                                      image: FileImage(_profileImage!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: _profileImage == null
                                ? const Icon(
                                    Icons.person,
                                    size: 80,
                                    color: Colors.grey,
                                  )
                                : null,
                          ),
                          // Кнопка добавления/изменения фото
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFFD04E4E),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
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
                    
                    // Отображение отзывов или сообщения об их отсутствии
                    _isLoadingReviews
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFFD04E4E)),
                      )
                    : _reviews.isEmpty
                      ? _buildEmptyReviewsMessage()
                      : Column(
                          children: _reviews.map((review) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildReviewCard(review),
                          )).toList(),
                        ),
                    
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
          
          // Всплывающее уведомление сверху
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
  
  // Виджет для отображения сообщения об отсутствии отзывов
  Widget _buildEmptyReviewsMessage() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.rate_review_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          const Text(
            'У вас пока нет отзывов',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF666666),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Отзывы появятся после заказов',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF999999),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  // Обновленный метод для отображения карточки отзыва
  Widget _buildReviewCard(Map<String, dynamic> review) {
    // Получаем рейтинг
    final int rating = review['rating'] as int;
    
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
              // Аватар автора отзыва
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.grey,
                  shape: BoxShape.circle,
                  image: review['authorImageUrl'] != null
                    ? DecorationImage(
                        image: NetworkImage(review['authorImageUrl']),
                        fit: BoxFit.cover,
                      )
                    : null,
                ),
                child: review['authorImageUrl'] == null
                  ? const Icon(
                      Icons.person,
                      color: Colors.white,
                      size: 24,
                    )
                  : null,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Имя автора отзыва
                  Text(
                    review['authorName'] as String,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // Звездный рейтинг
                  Row(
                    children: List.generate(5, (index) {
                      return Icon(
                        index < rating ? Icons.star : Icons.star_border,
                        color: Colors.yellow,
                        size: 14,
                      );
                    }),
                  ),
                ],
              ),
              const Spacer(),
              // Дата отзыва
              if (review['createdAt'] != null)
                Text(
                  _formatDate(review['createdAt'] as Timestamp),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Текст отзыва
          Text(
            review['text'] as String,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
  
  // Метод для форматирования даты
  String _formatDate(Timestamp timestamp) {
    final DateTime date = timestamp.toDate();
    return '${date.day}.${date.month}.${date.year}';
  }
} 