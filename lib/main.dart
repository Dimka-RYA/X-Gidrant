import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_config.dart';
import 'auth/login_screen.dart';
import 'auth/register_screen.dart';
import 'main_screen.dart';
import 'engineer_main_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Основная функция запуска приложения
void main() async {
  // Инициализация Flutter необходима для Firebase
  WidgetsFlutterBinding.ensureInitialized();
  
  // Показываем загрузочный экран до инициализации Firebase
  runApp(const LoadingScreen());
  
  // Асинхронно инициализируем Firebase
  try {
    await Firebase.initializeApp(
      options: FirebaseOptions(
        apiKey: FirebaseConfig.apiKey,
        appId: FirebaseConfig.appId,
        messagingSenderId: FirebaseConfig.messagingSenderId,
        projectId: FirebaseConfig.projectId,
        authDomain: FirebaseConfig.authDomain,
        storageBucket: FirebaseConfig.storageBucket,
        measurementId: FirebaseConfig.measurementId,
      ),
    );
    debugPrint("Firebase успешно инициализирован");
    
    // Небольшая задержка, чтобы анимация загрузки была видна
    await Future.delayed(const Duration(seconds: 3));
    
    // Запускаем основное приложение после инициализации
    runApp(const MyApp());
  } catch (e) {
    debugPrint("Ошибка инициализации Firebase: $e");
    runApp(const AppWithError());
  }
}

// Виджет загрузочного экрана с GIF анимацией
class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _isImageError = false;

  @override
  void initState() {
    super.initState();
    
    // Инициализируем анимацию для резервного варианта
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    
    _animationController.repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'X-Гидрант',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: Colors.white, // Меняем черный фон на белый
        body: Center( // Центрируем всё содержимое
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center, // Горизонтальное центрирование
            children: [
              !_isImageError 
                ? SizedBox(
                    width: 300,  // Размер контейнера с гифкой
                    height: 300,
                    child: Center( // Дополнительное центрирование гифки внутри контейнера
                      child: Stack(
                        alignment: Alignment.center, // Центрируем содержимое стека
                        children: [
                          Image.asset(
                            'lib/assets/loading.gif',
                            errorBuilder: (context, error, stackTrace) {
                              debugPrint('Ошибка загрузки GIF: $error');
                              
                              // Отмечаем ошибку и показываем запасную анимацию
                              if (!_isImageError) {
                                Future.microtask(() {
                                  if (mounted) {
                                    setState(() {
                                      _isImageError = true;
                                    });
                                  }
                                });
                              }
                              
                              return AnimatedBuilder(
                                animation: _animationController,
                                builder: (context, child) {
                                  return Container(
                                    width: 150, // Увеличиваем размер запасной анимации
                                    height: 150,
                                    padding: const EdgeInsets.all(8.0),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Внешний круг
                                        CircularProgressIndicator(
                                          color: Colors.red,
                                          value: _animation.value,
                                          strokeWidth: 4.0,
                                        ),
                                        // Внутренний круг
                                        Positioned(
                                          child: CircularProgressIndicator(
                                            color: Colors.red.shade300,
                                            value: 1 - _animation.value,
                                            strokeWidth: 4.0,
                                          ),
                                        ),
                                        // Центральная точка
                                        Container(
                                          width: 15,
                                          height: 15,
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.red.withOpacity(0.5),
                                                blurRadius: 10,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                            fit: BoxFit.contain, // Контейнер содержит все изображение
                            gaplessPlayback: true, // Обеспечивает непрерывное отображение
                          ),
                          // Белый блок для маскировки логотипа в правом нижнем углу
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 50,
                              height: 75,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Container(
                        width: 150, // Увеличиваем размер запасной анимации
                        height: 150,
                        padding: const EdgeInsets.all(8.0),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Внешний круг
                            CircularProgressIndicator(
                              color: Colors.red,
                              value: _animation.value,
                              strokeWidth: 4.0,
                            ),
                            // Внутренний круг
                            Positioned(
                              child: CircularProgressIndicator(
                                color: Colors.red.shade300,
                                value: 1 - _animation.value,
                                strokeWidth: 4.0,
                              ),
                            ),
                            // Центральная точка
                            Container(
                              width: 15,
                              height: 15,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.5),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

// Виджет для отображения ошибки инициализации Firebase
class AppWithError extends StatelessWidget {
  const AppWithError({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'X-Гидрант',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 24),
              const Text(
                'Ошибка инициализации приложения',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Не удалось подключиться к сервисам. Проверьте подключение к интернету.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  // Перезапускаем приложение
                  main();
                },
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'X-Гидрант',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: _getLandingPage(),
      routes: {
        '/login': (context) {
          print('Переход на экран входа');
          return const LoginScreen();
        },
        '/register': (context) {
          print('Переход на экран регистрации');
          return const RegisterScreen();
        },
        '/main': (context) {
          print('Переход на главный экран клиента');
          return const MainScreen();
        },
        '/engineer': (context) {
          print('Переход на главный экран инженера');
          return const EngineerMainScreen();
        },
      },
    );
  }
  
  Widget _getLandingPage() {
    print('===========================================================');
    print('LANDING PAGE: Начало _getLandingPage: определяем пользователя...');
    return FutureBuilder<User?>(
      // Используем Future вместо Stream для начальной загрузки
      future: _getCurrentUser(),
      builder: (context, snapshot) {
        // Показываем индикатор загрузки, пока ждем данные
        if (snapshot.connectionState == ConnectionState.waiting) {
          print('LANDING PAGE: Ожидание данных пользователя...');
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        
        // Если есть ошибка, показываем экран входа
        if (snapshot.hasError) {
          print('LANDING PAGE: Ошибка при получении данных пользователя: ${snapshot.error}');
          return const LoginScreen();
        }
        
        // Проверяем наличие пользователя
        final user = snapshot.data;
        if (user == null) {
          print('LANDING PAGE: Пользователь не авторизован, показываем экран входа');
          return const LoginScreen();
        }
        
        // Пользователь найден, проверяем его роль
        print('LANDING PAGE: Пользователь найден: ${user.email}, UID: ${user.uid}. Проверяем роль в Firestore...');
        
        // Проверяем роль пользователя напрямую в Firestore
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, docSnapshot) {
            if (docSnapshot.connectionState == ConnectionState.waiting) {
              print('LANDING PAGE: Ожидание данных из Firestore...');
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }
            
            // Проверяем, существует ли документ и какая у него роль
            String role = 'user'; // По умолчанию
            
            if (docSnapshot.hasData && docSnapshot.data!.exists) {
              // Данные получены
              final userData = docSnapshot.data!.data() as Map<String, dynamic>?;
              print('LANDING PAGE: Данные пользователя из Firestore: $userData');
              
              if (userData != null && userData.containsKey('role')) {
                role = userData['role'] as String;
                print('LANDING PAGE: Роль пользователя из Firestore: "$role"');
                
                // Обрезаем пробелы и приводим к нижнему регистру для надежного сравнения
                role = role.trim().toLowerCase();
                
                // Сохраняем роль через публичный метод AuthService
                AuthService().saveUserRole(role);
              } else {
                print('LANDING PAGE: Поле role не найдено в документе пользователя');
              }
            } else {
              print('LANDING PAGE: Документ пользователя не найден в Firestore, используем роль по умолчанию: "$role"');
            }
            
            // Определяем экран на основе роли (нечувствительно к регистру)
            final isEngineer = role.trim().toLowerCase() == 'engineer'.toLowerCase();
            print('LANDING PAGE: Результат сравнения: "$role" == "engineer" = $isEngineer');
            
            if (isEngineer) {
              print('LANDING PAGE: ПЕРЕХОД: Открываем экран инженера (EngineerMainScreen)');
              print('===========================================================');
              return const EngineerMainScreen();
            } else {
              print('LANDING PAGE: ПЕРЕХОД: Открываем экран клиента (MainScreen)');
              print('===========================================================');
              return const MainScreen();
            }
          },
        );
      },
    );
  }
  
  // Метод для получения текущего пользователя без блокировки UI
  Future<User?> _getCurrentUser() async {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (e) {
      debugPrint('Ошибка при получении текущего пользователя: $e');
      return null;
    }
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('X-Gidrant'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await AuthService().signOut();
            },
          ),
        ],
      ),
      body: const Center(
        child: Text('Вы успешно вошли в систему!'),
      ),
    );
  }
}
