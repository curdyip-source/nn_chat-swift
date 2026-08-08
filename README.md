<div align="center">

# 📱 NufNaf Chat — iOS

**Нативный iOS-клиент корпоративного чата с CRM: живая переписка, заказы, склад и документы прямо в кармане.**

![iOS](https://img.shields.io/badge/iOS-26.0+-000000?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5-FA7343?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-UIKit_hybrid-0071E3?logo=swift&logoColor=white)
![Xcode](https://img.shields.io/badge/Xcode-15+-147EFB?logo=xcode&logoColor=white)
![APNs](https://img.shields.io/badge/Push-APNs-FF2D55?logo=apple&logoColor=white)

</div>

---

## 📖 О приложении

**NufNaf Chat** — нативное iOS-приложение для команд, объединяющее **мессенджер** и **CRM**. Переписка в реальном времени с вложениями и @упоминаниями соседствует с управлением заказами, складом, товарами и документами. Приложение работает с бэкендом [nn_chat](../nn_chat).

Архитектура — **гибрид SwiftUI + UIKit**: интерфейс и состояние на SwiftUI, а высокопроизводительная лента сообщений построена на `UICollectionView` с нативной синхронизацией клавиатуры. Под капотом — продуманный менеджмент сессии с проактивным обновлением токенов, биометрический вход и push-уведомления Apple.

---

## ✨ Возможности

- 💬 **Чат в реальном времени** — текст, файлы и изображения
- 🏷️ **@Упоминания** — автодополнение участников
- ✏️ **Редактирование, удаление и ответы** на сообщения
- ⚡ **Оптимистичная отправка** — локальные статусы `pending / sent / failed` с возможностью повтора
- 🔔 **Push-уведомления (APNs)** — с автоопределением sandbox / production и маршрутизацией на чат или заказ
- 🔐 **Биометрия** — вход по Face ID / Touch ID
- 🔄 **Проактивное обновление JWT** — фоновое продление сессии (за 90 сек до истечения) без выкидывания на логин
- 🔎 **Фильтры и поиск** — по дате, типу, заведению, способу заказа и статусу
- 📦 **CRM-модуль** — заказы, склад, регистрации товаров, документы
- ✅ **Задачи** — тудулист со смарт-списками и своими списками, сроки со временем, метки, подзадачи, перетаскивание; задачи заказов с ответственными видны прямо в карточке заказа
- 🚚 **СДЭК** — создание накладной (город/ПВЗ по названию, тариф, доп. услуги), трек и авто-статусы в карточке, PDF-накладные в чате заказа, пересоздание
- 👤 **Профиль** — редактирование и загрузка фото
- ⌨️ **Нативная клавиатура** — синхронизация композера через `keyboardLayoutGuide`
- 🌙 **Тёмная тема** — единый стиль интерфейса

---

## 🛠️ Технологии

- **Swift 5**, **SwiftUI** + **UIKit** (гибрид)
- **Combine** — реактивное состояние
- **UserNotifications** — push (APNs)
- **LocalAuthentication** — Face ID / Touch ID
- Только Apple-фреймворки — **без сторонних SPM-зависимостей**

**Архитектура:** MVVM на `ObservableObject` с `@MainActor`-изоляцией, внедрение зависимостей через клиентские сервисы.

---

## 🗂️ Структура проекта

```
NufNaf Chat/
├── App/                      # точка входа, AppDelegate, корневая навигация
│   ├── myclearprojectIOSApp.swift
│   └── ContentView.swift     # состояния: loading / login / authenticated / awaitingApproval
├── Core/                     # инфраструктура
│   ├── Config/               # AppConfig, NotificationRouter, биометрия
│   └── Theme/                # тёмная тема и константы вёрстки
├── Features/
│   ├── Auth/                 # вход, регистрация, сессия
│   │   ├── Models/           # AuthUser, AuthResponse, LoginRequest, ...
│   │   ├── Networking/       # AuthAPIClient
│   │   ├── State/            # AppSession (рефреш токенов, биометрия)
│   │   └── Views/            # LoginView, RegisterView, InactiveAccountView
│   └── Home/                 # чат + CRM
│       ├── Models/           # сообщения, заказы, склад, контакты, ...
│       ├── Networking/       # HomeAPIClient
│       ├── State/            # HomeStore
│       └── Views/            # ChatConversationView (UICollectionView), HomeView, ...
└── Shared/                   # переиспользуемые компоненты вёрстки
```

---

## 🚀 Сборка и запуск

```bash
# Открыть проект в Xcode
open "NufNaf Chat.xcodeproj"
```

Выбрать схему и нажать ▶︎ (`Cmd + R`):

- **NufNaf Chat (Local)** — Debug-сборка на **локальный** бэкенд (build-фаза подставляет `http://<IP-Mac-в-Wi-Fi>:8001/api/v1`, IP определяется автоматически). Для теста на живом iPhone подними локальный стек `nn_chat` (`docker compose up`, API на `:8001`) и держи телефон в той же Wi-Fi.
- **NufNaf Chat (Prod)** — Release-сборка на прод (`chat.nufnafchat.su`). **Archive для TestFlight — всегда эта схема.**

Из командной строки:

```bash
# Сборка под симулятор (локальная схема)
xcodebuild -project "NufNaf Chat.xcodeproj" -scheme "NufNaf Chat (Local)" -configuration Debug

# Тесты
xcodebuild test -project "NufNaf Chat.xcodeproj" -scheme "NufNaf ChatTests"
```

### Требования

| | |
|---|---|
| **Xcode** | 15+ |
| **iOS (deployment target)** | 26.0+ |
| **Устройства** | iPhone + iPad |
| **Swift** | 5 |
| **Bundle ID** | `com.NufNaf.Vorobev` |
| **Версия** | 2.0 |

> 🔐 Для push-уведомлений и подписи нужен аккаунт Apple Developer. Подпись настроена автоматически (Xcode-managed).

---

## 🔗 Подключение к бэкенду

Приложение работает с REST API через HTTPS и Bearer-токены.

| Параметр | Значение по умолчанию | Переопределяется через |
|----------|----------------------|------------------------|
| API base URL | `https://chat.nufnafchat.su/api/v1` | `Info.plist → API_BASE_URL` |
| Media base URL | `https://chat.nufnafchat.su/media` | `Info.plist → MEDIA_BASE_URL` |

Значение `API_BASE_URL` выбирается **схемой при сборке**: Local (Debug) — build-фаза `Set Local API host` (`Scripts/inject_local_api_host.sh`) подставляет локальный адрес; Prod (Release) — остаётся прод из `Info.plist`. `AppConfig.swift` читает ключ из Info.plist (fallback — прод).

Основные эндпоинты: `POST /auth/login`, `POST /auth/refresh`, `GET /auth/me`, `GET·POST·PUT·DELETE /messages`, `GET /users/participants`, `POST /users/me/profile-photo`, `GET /reference-data`, а также CRM-маршруты (`/orders`, `/products`, `/contacts`, `/inventory`).

---

## 🧩 Технические детали

- **Лента сообщений** — инвертированный `UICollectionView` с `UIHostingConfiguration` (SwiftUI-ячейки в UIKit) и дешёвым хешированием контента для диффинга
- **Сессия** — коалесинг запросов на рефреш, exponential backoff, мягкая деградация при сбоях сети
- **APNs** — окружение определяется автоматически из `aps-environment` в provisioning profile
- **Доставка** — оптимистичные апдейты с серверной сверкой, повтор неудачных сообщений
- **Локализация** — интерфейс на русском языке

---

## 🔗 Связанные проекты

- ⚙️ [**nn_chat**](../nn_chat) — бэкенд (FastAPI) и веб-панель администратора
