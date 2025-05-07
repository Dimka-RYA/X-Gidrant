# X-Гидрант - Приложение для гидрантов

Проект Flutter с аутентификацией Firebase.

## Настройка Firebase

1. Создайте проект в [Firebase Console](https://console.firebase.google.com/)
2. Зарегистрируйте приложение Flutter
3. Загрузите конфигурационные файлы для каждой платформы (Android, iOS, Web)
4. Обновите данные в файле `lib/firebase_config.dart` с вашими параметрами

## Настройка Git

В проекте уже выполнены следующие команды:

```
git init
git add .
git commit -m "первый коммит"
git branch -M main
git remote add origin https://github.com/Dimka-RYA/X-Gidrant.git
```

Для отправки изменений выполните:

```
git push origin main
```

## Запуск проекта

```
flutter pub get
flutter run
```

## Использование кастомной GIF-анимации

Для работы приложения требуется добавить GIF-анимацию для индикатора обновления:

1. Поместите файл "Animation - 1746311825329.gif" в директорию `lib/assets/`
2. Проверьте, что в файле `pubspec.yaml` есть следующие строки:
   ```yaml
   flutter:
     assets:
       - lib/assets/
   ```
3. Запустите команду `flutter pub get` для обновления зависимостей
4. Запустите приложение с помощью `flutter run`

## Замена GIF-анимации

Если вы хотите использовать другую GIF-анимацию:

1. Переименуйте ваш GIF-файл в "Animation - 1746311825329.gif" или
2. Измените путь в файле `lib/screens/home_screen.dart` в методе `_buildWaterDropLoadingIndicator()`:
   ```dart
   Image.asset(
     'lib/assets/ВАШ_ФАЙЛ.gif',
     fit: BoxFit.contain,
   ),
   ```
