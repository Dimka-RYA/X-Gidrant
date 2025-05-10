// Файл с примером Firestore правил для проекта
// Эти правила должны быть скопированы в Firebase Console

/*
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Улучшенная функция для проверки администратора
    function isAdmin() {
      let auth = request.auth;
      // Проверяем, аутентифицирован ли пользователь
      let isAuthenticated = auth != null;
      // Проверяем, существует ли документ пользователя
      let userExists = isAuthenticated && exists(/databases/$(database)/documents/users/$(auth.uid));
      // Получаем роль пользователя, если документ существует
      let isAdminRole = userExists && get(/databases/$(database)/documents/users/$(auth.uid)).data.role == 'admin';
      
      return isAuthenticated && userExists && isAdminRole;
    }
    
    // Функция для проверки диспетчера
    function isDispatcher() {
      let auth = request.auth;
      // Проверяем, аутентифицирован ли пользователь
      let isAuthenticated = auth != null;
      // Проверяем, существует ли документ пользователя
      let userExists = isAuthenticated && exists(/databases/$(database)/documents/users/$(auth.uid));
      // Получаем роль пользователя, если документ существует
      let isDispatcherRole = userExists && get(/databases/$(database)/documents/users/$(auth.uid)).data.role == 'dispatcher';
      
      return isAuthenticated && userExists && isDispatcherRole;
    }
    
    // Функция для проверки инженера
    function isEngineer() {
      let auth = request.auth;
      // Проверяем, аутентифицирован ли пользователь
      let isAuthenticated = auth != null;
      // Проверяем, существует ли документ пользователя
      let userExists = isAuthenticated && exists(/databases/$(database)/documents/users/$(auth.uid));
      // Получаем роль пользователя, если документ существует
      let isEngineerRole = userExists && get(/databases/$(database)/documents/users/$(auth.uid)).data.role == 'engineer';
      
      return isAuthenticated && userExists && isEngineerRole;
    }
    
    // Функция для проверки администратора или диспетчера
    function isAdminOrDispatcher() {
      return isAdmin() || isDispatcher();
    }
    
    // Функция для проверки администратора, диспетчера или инженера
    function isStaff() {
      return isAdmin() || isDispatcher() || isEngineer();
    }
    
    // Правила для коллекции пользователей
    match /users/{userId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && (
        request.auth.uid == userId || isAdmin()
      );
    }
    
    // Явные правила для сервисных категорий
    match /service_categories/{categoryId} {
      allow read: if true;
      allow write: if isAdmin();
    }
    
    // Правила для услуг
    match /services/{serviceId} {
      allow read: if true;
      allow write: if isAdmin();
    }
    
    // Правила для заказов - разрешаем инженерам обновлять геолокацию, а клиентам - читать её
    match /orders/{orderId} {
      // Разрешаем инженерам читать все заказы при запросах с фильтрами
      allow list: if request.auth != null && isEngineer();
      
      // Правила для чтения отдельного документа
      allow get: if request.auth != null && (
        resource.data.clientId == request.auth.uid || 
        resource.data.assignedTo == request.auth.uid || 
        isAdminOrDispatcher()
      );
      
      // Пользователи могут создавать заказы
      allow create: if request.auth != null;
      
      // Пользователи могут изменять свои заказы полностью
      // Инженеры - назначенные им, админы и диспетчеры - любые
      allow update: if request.auth != null && (
        resource.data.clientId == request.auth.uid || 
        resource.data.assignedTo == request.auth.uid || 
        isAdminOrDispatcher()
      );
      
      // Админы, диспетчеры и инженеры могут удалять заказы
      allow delete: if isAdminOrDispatcher() || 
        (isEngineer() && resource.data.assignedTo == request.auth.uid);
    }
    
    // Правила для истории заказов
    match /order_history/{historyId} {
      allow read: if request.auth != null;
      allow create: if isStaff();
      allow update: if isAdminOrDispatcher();
      allow delete: if isAdmin();
    }
    
    // Правила для отзывов
    match /reviews/{reviewId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update: if request.auth != null && (
        (resource.data.clientId == request.auth.uid) || 
        (resource.data.engineerId == request.auth.uid) || 
        isAdmin()
      );
      allow delete: if isAdmin();
    }
    
    // Правила для флагов отзывов
    match /user_reviews_flags/{flagId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update: if request.auth != null && (
        resource.data.userId == request.auth.uid || isAdmin()
      );
      allow delete: if isAdmin();
    }
    
    // Правила для уведомлений
    match /notifications/{notificationId} {
      allow read: if request.auth != null && (
        resource.data.userId == request.auth.uid || isAdminOrDispatcher()
      );
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null && (
        resource.data.userId == request.auth.uid || isAdminOrDispatcher()
      );
    }
    
    // Общие правила для других коллекций
    match /{document=**} {
      allow read: if request.auth != null;
      allow write: if isAdminOrDispatcher();
    }
  }
}
*/ 