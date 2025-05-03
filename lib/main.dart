import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_config.dart';
import 'auth/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  bool firebaseInitialized = false;
  
  try {
    // Проверяем, не инициализирован ли Firebase уже
    List<FirebaseApp> apps = Firebase.apps;
    if (apps.isEmpty) {
      // Инициализация Firebase, если еще не инициализирован
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
    } else {
      Firebase.app(); // Используем уже инициализированное приложение
    }
    
    // Проверка корректности конфигурации
    if (FirebaseConfig.apiKey == "ЗАПОЛНИТЕ_СВОИМ_API_KEY" ||
        FirebaseConfig.projectId == "ЗАПОЛНИТЕ_СВОИМ_PROJECT_ID") {
      firebaseInitialized = false;
      print("ВНИМАНИЕ: Вы не заполнили данные Firebase в файле конфигурации!");
    } else {
      firebaseInitialized = true;
    }
  } catch (e) {
    print("Ошибка инициализации Firebase: $e");
    firebaseInitialized = false;
  }
  
  runApp(MainApp(firebaseInitialized: firebaseInitialized));
}

class MainApp extends StatelessWidget {
  final bool firebaseInitialized;
  
  const MainApp({super.key, this.firebaseInitialized = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'X-Gidrant',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: firebaseInitialized 
        ? _buildAuthFlow() 
        : _buildFirebaseNotConfigured(),
    );
  }
  
  Widget _buildAuthFlow() {
    return StreamBuilder<User?>(
      stream: AuthService().user,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final User? user = snapshot.data;
          if (user == null) {
            // Пользователь не авторизован
            return const LoginScreen();
          }
          // Пользователь авторизован
          return const HomeScreen();
        }
        // Загрузка
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }
  
  Widget _buildFirebaseNotConfigured() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('X-Gidrant - Требуется настройка'),
        backgroundColor: Colors.orange,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.orange,
              size: 80,
            ),
            const SizedBox(height: 16),
            const Text(
              'Firebase не настроен',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Необходимо заполнить данные Firebase в файле:\n'
              'lib/firebase_config.dart',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const Text(
              '1. Создайте проект в Firebase Console\n'
              '2. Зарегистрируйте Android приложение\n'
              '3. Заполните данные из google-services.json\n'
              '4. Перезапустите приложение',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.left,
            ),
          ],
        ),
      ),
    );
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
