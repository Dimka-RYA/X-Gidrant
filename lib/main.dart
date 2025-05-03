import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_config.dart';
import 'auth/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация Firebase
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
  
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'X-Gidrant',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
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
