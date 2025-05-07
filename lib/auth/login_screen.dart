import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'register_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _error = '';
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _error = '';
        _isLoading = true;
      });

      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      try {
        final success = await _authService.signIn(email, password);
        
        if (!mounted) return;
        
        if (success) {
          // Проверяем роль пользователя после входа
          final role = await _authService.getUserRole();
          final isEngineer = await _authService.isEngineer();
          print('ВХОД: Успешный вход, роль: $role, инженер: $isEngineer');
          
          // Получаем актуальные данные из Firestore
          final user = _authService.currentUser;
          if (user != null) {
            try {
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get();
              
              if (userDoc.exists) {
                final userData = userDoc.data();
                if (userData != null && userData.containsKey('role')) {
                  final firestoreRole = userData['role'].toString().trim().toLowerCase();
                  print('ВХОД: Роль из Firestore: "$firestoreRole"');
                  
                  // Определяем направление на основе данных из Firestore
                  if (firestoreRole == 'engineer'.toLowerCase()) {
                    print('ВХОД: Перенаправление на экран инженера (из Firestore)');
                    Navigator.pushReplacementNamed(context, '/engineer');
                    return;
                  }
                }
              }
            } catch (e) {
              print('ВХОД: Ошибка при получении данных из Firestore: $e');
            }
          }
          
          // Перенаправляем на соответствующий экран в зависимости от кэшированной роли
          if (isEngineer) {
            print('ВХОД: Перенаправление на экран инженера (из кэша)');
            Navigator.pushReplacementNamed(context, '/engineer');
          } else {
            print('ВХОД: Перенаправление на экран клиента');
            Navigator.pushReplacementNamed(context, '/main');
          }
        } else {
          setState(() {
            _error = 'Не удалось войти. Проверьте логин и пароль.';
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Ошибка входа: ${e.toString()}';
        });
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('lib/assets/image 10.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    // Лого по центру
                    Center(
                      child: Column(
                        children: [
                          Image.asset(
                            'lib/assets/image.png',
                            width: 80,
                            height: 80,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'ИНЖИНИРИНГОВАЯ КОМПАНИЯ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Авторизация',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    // Поле логина
                    const Text(
                      'Логин',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: 'Введите email',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                        ),
                        filled: false,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.red, width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.red, width: 2.0),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      style: const TextStyle(color: Colors.black87),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите email';
                        }
                        return null;
                      },
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Поле пароля
                    const Text(
                      'Пароль',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: 'Введите пароль',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                        ),
                        filled: false,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.red, width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.red, width: 2.0),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      style: const TextStyle(color: Colors.black87),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Введите пароль';
                        }
                        return null;
                      },
                    ),
                    
                    if (_error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _error,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    
                    const SizedBox(height: 40),
                    
                    // Кнопка входа
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            setState(() {
                              _isLoading = true;
                            });
                            
                            try {
                              final email = _emailController.text.trim();
                              final password = _passwordController.text.trim();
                              final success = await _authService.signIn(email, password);
                              
                              if (!mounted) return;
                              
                              if (success) {
                                // Проверяем роль пользователя после входа
                                final role = await _authService.getUserRole();
                                final isEngineer = await _authService.isEngineer();
                                print('ВХОД: Успешный вход, роль: $role, инженер: $isEngineer');
                                
                                // Получаем актуальные данные из Firestore
                                final user = _authService.currentUser;
                                if (user != null) {
                                  try {
                                    final userDoc = await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(user.uid)
                                        .get();
                                    
                                    if (userDoc.exists) {
                                      final userData = userDoc.data();
                                      if (userData != null && userData.containsKey('role')) {
                                        final firestoreRole = userData['role'].toString().trim().toLowerCase();
                                        print('ВХОД: Роль из Firestore: "$firestoreRole"');
                                        
                                        // Определяем направление на основе данных из Firestore
                                        if (firestoreRole == 'engineer'.toLowerCase()) {
                                          print('ВХОД: Перенаправление на экран инженера (из Firestore)');
                                          Navigator.pushReplacementNamed(context, '/engineer');
                                          return;
                                        }
                                      }
                                    }
                                  } catch (e) {
                                    print('ВХОД: Ошибка при получении данных из Firestore: $e');
                                  }
                                }
                                
                                // Перенаправляем на соответствующий экран в зависимости от кэшированной роли
                                if (isEngineer) {
                                  print('ВХОД: Перенаправление на экран инженера (из кэша)');
                                  Navigator.pushReplacementNamed(context, '/engineer');
                                } else {
                                  print('ВХОД: Перенаправление на экран клиента');
                                  Navigator.pushReplacementNamed(context, '/main');
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Неверный email или пароль'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (!mounted) return;
                              
                              print('Ошибка входа: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Ошибка: ${e.toString()}'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            } finally {
                              if (mounted) {
                                setState(() {
                                  _isLoading = false;
                                });
                              }
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF5555),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Войти',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Кнопка перехода на регистрацию
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red, width: 1.0),
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          backgroundColor: Colors.transparent,
                        ),
                        child: const Text(
                          'Зарегистрироваться',
                          style: TextStyle(
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 