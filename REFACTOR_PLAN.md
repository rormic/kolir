# План рефакторингу Kolir

Дата: 2026-11-21  
Статус: Фаза A виконана (кроки 1–20). Триває Фаза B.

## 1. Мета та незмінні вимоги

Привести структуру проєкту до єдиної, зрозумілої схеми, прибрати підтверджений мертвий код і централізувати повторювані дизайн-значення без зміни поточного вигляду та поведінки.

Обов’язкові обмеження:

- Не змінювати вигляд, анімації, розміри, кольори, відступи, порядок елементів або взаємодію.
- Не додавати нові залежності.
- Не «нормалізувати» близькі числа: `130`, `140`, `150` залишаються різними значеннями.
- Не перейменовувати IPC targets, layer namespaces, CLI-команди, формати JSON і публічні API без окремого рішення.
- Не виправляти сторонні функціональні дефекти під виглядом рефакторингу.
- Не виправляти масово наявні `qmllint` warnings. Перевіряються лише нові помилки та регресії.
- Кожен крок має бути окремим, оборотним changeset.
- Один крок стосується одного основного компонента або файла; прямі imports/виклики оновлюються лише там, де це потрібно для працездатності.

## 2. Поточний стан

У `config/quickshell` є 46 QML-файлів, приблизно 11 339 рядків QML. Основні проблеми:

- `theme/` поєднує дизайн-токени та runtime-сервіси.
- `bar/components/` містить примітиви, віджети, tray, великі popup-и й MPRIS-логіку.
- `InternetPage`, `Launcher`, `BrightnessPopup`, `HyprsunsetService`, `SoundControls`, `SettingsMenu`, `BluetoothPage`, `AudioService`, `RecordingSetup` і `NowPlaying` поєднують стан, процеси та представлення.
- Python-хелпери розкидані між `scripts/` і `launcher/`.
- У `config/hypr/scripts/` змішані `snake_case` і `kebab-case`.
- `VolumeOsd` ↔ `BrightnessOsd`, `VolumePopup` ↔ `BrightnessPopup`, output/input cards і sink/source lists мають значне дублювання.
- `screen-record.sh` поєднує життєвий цикл запису, аудіо, вибір кодеків і роботу з моніторами.

### Підтверджений мертвий код

Не інстантуються:

- `config/quickshell/Button.qml`;
- `config/quickshell/corners/Corner.qml`;
- `config/quickshell/bar/components/Island.qml`;
- `config/quickshell/bar/components/PixelBox.qml`.

Підтверджені невикористані imports:

- `Quickshell` у `settings/SettingsMenu.qml`;
- `Quickshell` у `theme/BrightnessService.qml`;
- `Quickshell` у `bar/components/Workspaces.qml`;
- `".."` у `notification/Notification.qml`.

Підтверджені невикористані або write-only властивості:

- `HyprsunsetService.expectedOn`;
- `SettingsMenu.popoutWidth`;
- `Tray.itemCount`;
- `Pill.iconItem`, `Pill.textItem`;
- `InternetPage.wifiState`, `busyAction`, `pollGeneration`;
- зайвий `required property int index` у delegate мережі;
- write-only поля моделей `AudioService`: `index`, `codec`, `cards[].address`, `actionQueue[].description`.

Інертні сигнали:

- `BluetoothPage.close()` і відповідний `onClose` у `SettingsMenu`;
- `InternetPage.close()` і відповідний `onClose` у `SettingsMenu`.

Підтверджені невикористані design tokens:

- `Dimensions.insideBarSize`, `bar.contentHeight` (використовується лише всередині `insideBarSize`);
- `Dimensions.radius.extraSmall`, `radius.extraLargeIncreased`;
- `Dimensions.control.touchTarget`;
- `Dimensions.padding.horizontal`, `padding.vertical`;
- `Dimensions.spacing.none`, `spacing.extraSmall`, `spacing.medium`, `spacing.large`;
- `Typography.mainFont`, `size.bodySmall`, `size.titleMedium`, `size.headlineSmall`, `size.headlineMedium`;
- `Icons.stop`, `Icons.wifiLock`;
- невикористані Material-ролі в `Colors`, перелік яких потрібно повторно підтвердити grep безпосередньо перед кроком;
- сумісний об’єкт `Colors.colors`.

Оскільки проєкт не використовує `Loader`, `Qt.createComponent`, `Qt.createQmlObject` або динамічні QML-шляхи, статичний пошук посилань є достатнім для цих висновків.

### Що не вважати мертвим кодом

- `IpcHandler`-методи: вони можуть викликатися через `qs ipc call`.
- Аргументи callback-функцій, форма яких визначена Quickshell API.
- Закоментований альтернативний `profile` у `hyprsunset.conf`: це документація режиму, а не вимкнений код.
- Невикористані зараз токени, які мають явне архітектурне значення та залишаються в публічному дизайн-словнику після свідомого рішення.
- Сирі desktop icon names у `AudioService`: це не Material-лігатури з `Icons`.

## 3. Правила для констант

Не виносити всі числа без розбору.

- `Dimensions` — повторювані геометричні значення та спільні метрики.
- `Typography` — шрифти й type scale.
- `Icons` — Material Symbols names.
- `Motion` — повторювані ролі UI-анімацій: `color`, `hover`, `press`, `popupEnter`, `popupExit`, `listEnter`, `listExit`, `osd`, `spin`.
- Локальні `readonly` властивості — розміри конкретного popup, optical offsets, інтервали процесів, thresholds.
- Локальні доменні константи — FPS, bitrate, CRF, температури, search scores, NOAA-коефіцієнти.
- Без токенів — `0`/`1`, SVG coordinates, математичні коефіцієнти, координати accent dots та одноразові optical tweaks.

Не змінювати без синхронної перевірки Hyprland:

- `Dimensions.bar.height = 30`;
- `Dimensions.frame.thickness = 4`;
- `Dimensions.frame.radius = 30`.

## 4. Цільова структура

Існуючі дрібні bar-віджети не переносити лише заради переміщення. Структура має зменшувати зв’язність, а не створювати великий import churn.

```text
config/
├── quickshell/
│   ├── shell.qml
│   ├── colors.json
│   ├── .qmlls.ini
│   │
│   ├── theme/                    # Тільки візуальні singletons
│   │   ├── Colors.qml
│   │   ├── Dimensions.qml
│   │   ├── Typography.qml
│   │   ├── Icons.qml
│   │   ├── Motion.qml
│   │   └── qmldir
│   │
│   ├── services/                 # Runtime singletons і path contracts
│   │   ├── AudioService.qml
│   │   ├── BrightnessService.qml
│   │   ├── HyprsunsetService.qml
│   │   ├── ShellPaths.qml
│   │   ├── qmldir
│   │   ├── audio/
│   │   │   └── AudioParser.js
│   │   └── hyprsunset/
│   │       ├── Solar.js
│   │       ├── Schedule.js
│   │       └── StateStore.qml
│   │
│   ├── components/               # Крос-feature контроли
│   │   ├── Toggle.qml
│   │   └── AnchoredPopup.qml
│   │
│   ├── bar/
│   │   ├── Bar.qml
│   │   ├── Frame.qml
│   │   └── components/
│   │       ├── Surface.qml
│   │       ├── Pill.qml
│   │       ├── IconButton.qml
│   │       ├── AppIcon.qml
│   │       ├── ProgressIndicator.qml
│   │       ├── VolumeSlider.qml
│   │       ├── ActiveWindow.qml
│   │       ├── Workspaces.qml
│   │       ├── NowPlaying.qml
│   │       ├── Clock.qml
│   │       ├── KeyboardLayout.qml
│   │       ├── Tray.qml
│   │       ├── TrayButton.qml
│   │       ├── TrayMenu.qml
│   │       ├── TrayMenuPane.qml
│   │       ├── RecordingStatus.qml
│   │       ├── Brightness.qml
│   │       ├── Volume.qml
│   │       ├── ThemeToggle.qml
│   │       ├── VolumePopup.qml
│   │       ├── SoundControls.qml
│   │       ├── BrightnessPopup.qml
│   │       ├── SunTimeCard.qml
│   │       ├── media/
│   │       │   ├── MarqueeText.qml
│   │       │   └── MprisController.qml
│   │       ├── sound/
│   │       │   ├── AudioDeviceCard.qml
│   │       │   ├── AudioDeviceList.qml
│   │       │   └── CodecChip.qml
│   │       └── nightLight/
│   │           ├── TemperatureCard.qml
│   │           ├── ScheduleCard.qml
│   │           └── TimeField.qml
│   │
│   ├── settings/
│   │   ├── SettingsMenu.qml
│   │   ├── MainPage.qml
│   │   ├── SettingsPageHeader.qml
│   │   ├── InternetPage.qml
│   │   ├── BluetoothPage.qml
│   │   ├── PasswordField.qml
│   │   ├── internet/
│   │   │   ├── NetworkController.qml
│   │   │   ├── EthernetCard.qml
│   │   │   ├── WifiConnectionForm.qml
│   │   │   └── WifiNetworkRow.qml
│   │   └── bluetooth/
│   │       └── BluetoothDeviceRow.qml
│   │
│   ├── launcher/
│   │   ├── Launcher.qml
│   │   ├── ClipboardController.qml
│   │   ├── SearchLogic.js
│   │   └── LauncherResultRow.qml
│   │
│   ├── notification/
│   │   ├── Notification.qml
│   │   └── NotificationCard.qml
│   │
│   ├── osd/
│   │   ├── OsdPanel.qml
│   │   ├── VolumeOsd.qml
│   │   └── BrightnessOsd.qml
│   │
│   ├── recording/
│   │   ├── RecordingSetup.qml
│   │   ├── RecordingOptions.qml
│   │   └── OptionRow.qml
│   │
│   └── scripts/
│       ├── favicon.py
│       ├── cliphist-store.py
│       └── cliphist-previews.py
│
└── hypr/
    └── scripts/
        ├── set-wallpaper.sh
        ├── select-wallpaper.sh
        ├── random-wallpaper.sh
        ├── generate-colors.sh
        ├── toggle-theme.sh
        ├── brightness.sh
        ├── screen-record.sh
        └── screen-record/
            ├── audio.sh
            ├── encoders.sh
            └── monitors.sh
```

### Межі володіння станом

- `NetworkController` створюється й живе всередині `InternetPage`, не як singleton: polling має залежати від visibility сторінки.
- `ClipboardController` створюється в root `Scope` лаунчера, не всередині `PanelWindow`: `wl-paste --watch` має працювати при закритому лаунчері.
- `BluetoothPage` не потребує нового service: `Quickshell.Bluetooth` уже є моделлю.
- `AnchoredPopup` не містить domain-specific refresh-on-open.
- `OsdPanel` не імпортує `AudioService` або `BrightnessService`.
- Сервіси зберігають поточні singleton-імена та публічні API.

## 5. Ручні перевірки

Автоматичні перевірки після кожного QML-кроку виконує `qml-mechanic`:

1. `/usr/lib/qt6/bin/qmllint` для кожного зміненого файла.
2. Перевірка логу після останнього `Reloading configuration...`.
3. Порівняння з baseline `/home/sakura/.cache/kolir/qml-baseline.log`.
4. Нові `ReferenceError`, `TypeError`, `is not a type`, `binding loop`, `Unable to assign` вважаються регресією.

Скорочення ручних перевірок:

| Код | Що перевірити |
|---|---|
| **BAR** | Bar у light/dark, active window, workspaces, clock, tray, pills, settings trigger, вузький/широкий екран. |
| **FRAME** | Рамка й rounded cut-out біля всіх країв; borders вікон не обрізаються; кліки проходять крізь frame; `hyprctl layers`. |
| **SET** | Main/Bluetooth/Internet, back, Escape, outside click, перемикання сторінок під час reveal. |
| **OSD** | Volume/brightness keys, повторні зміни, opacity/scale fade, остаточне приховування surface. |
| **SOUND** | Output/input sliders, wheel, mute, default devices, порожні списки, Bluetooth codec. |
| **NIGHT** | Toggle, presets, slider/wheel, fixed/sun schedule, location, IPC, стан після reload. |
| **MEDIA** | Play/pause у Firefox/Zen і звичайному плеєрі, next/previous, wheel, favicon fallback, marquee. |
| **LAUNCH** | App scoring, math, copy result, текстові/графічні clipboard items, delete, keyboard/mouse. |
| **NOTIFY** | Normal/critical notification, action, expiry, hover pause, dismiss. |
| **REC** | Keyboard/mouse, усі опції, start/stop, state file, подвійний виклик, PID lifecycle. |
| **NET** | Wi-Fi on/off, scan, open/secure/hidden network, password errors, forget, Ethernet details. |
| **BT** | Adapter toggles, discoverable, scan, connect/disconnect/forget, порожні стани. |
| **PATHS** | Робота з repo та через встановлені symlinks; favicon, clipboard previews і recording paths. |
| **THEME** | Light/dark toggle, regenerate colors, Hyprland/Foot/Neovim/hyprlock outputs. |

## 6. Виконавці

- **Основний агент** — архітектурні рішення, API нових компонентів, розбиття великих файлів, перенесення shell-логіки.
- **`qml-mechanic`** — підтверджене видалення, точні import/path/token replacements, переміщення файлів, `qmllint`, перевірка логів.
- Кожна задача `qml-mechanic` повинна містити точний список файлів, точну дію та явний список того, що заборонено змінювати.

## 7. Послідовність кроків

### Фаза A. Baseline і підтверджене прибирання — ✅ виконано

Усі кроки 1–20 завершені, кожен окремим комітом, з `qmllint`, повним перезапуском Quickshell і порівнянням консолі з baseline. Baseline збережено в `~/.cache/kolir/`.

| Крок | Дія | Коміт |
|---|---|---|
| 1 | Baseline: startup log, список warnings, smoke checklist | `cddba43` |
| 2 | Видалено `Button.qml`; разом з ним прибрано невикористаний `import ".."` у `notification/Notification.qml`, інакше холодний старт падав з `module ".." is not installed` | `d9934c2` |
| 3 | Видалено `corners/Corner.qml` і каталог `corners/` | `eb0693e` |
| 4 | Видалено `bar/components/Island.qml` | `282afa3` |
| 5 | Видалено `bar/components/PixelBox.qml` | `6670224` |
| 6 | `SettingsMenu.qml`: прибрано `import Quickshell` і `popoutWidth` | `6b8cf1c` |
| 7 | `Workspaces.qml`: прибрано `import Quickshell` | `a8331da` |
| 8 | `Tray.qml`: прибрано `itemCount` | `587fcdd` |
| 9 | `Pill.qml`: прибрано alias-и `iconItem`/`textItem` | `fe1feef` |
| 10 | `Dimensions.qml`: прибрано невикористані токени | `e7ce274` |
| 11 | `Typography.qml`: прибрано невикористані токени та `id: root` | `df94f18` |
| 12 | `Icons.qml`: прибрано `stop`, `wifiLock` | `81bd632` |
| 13 | `Colors.qml`: прибрано ролі з нульовими споживачами і `root.colors` | `9053c33` |
| 14 | `Notification.qml`: крок закрито порожнім комітом, бо import уже прибрано в кроці 2 | `18d403d` |
| 15 | `HyprsunsetService.qml`: прибрано `expectedOn` | `922f1ea` |
| 16 | `AudioService.qml`: прибрано write-only поля моделей | `83164a6` |
| 17 | `InternetPage.qml`: прибрано write-only стан і зайвий `index` | `583b6c1` |
| 18 | `generate_colors.sh`: прибрано закоментований legacy-код | `b1ed619` |
| 19 | `BluetoothPage.qml`: прибрано інертний `close()` | `5d6a0f6` |
| 20 | `InternetPage.qml`: прибрано інертний `close()` | `4433f5d` |

### Фаза B. Шляхи, іменування, токени

Нумерація продовжує Фазу A. У дужках — номер кроку в початковій редакції плану.

Доповнення до початкового плану: **ShellPaths** (кроки 21–22), **AnchoredPopup** (крок 39), **SettingsPageHeader** (крок 41), **RecordingOptions** (крок 51), **PasswordField** (крок 56).

21. **Створити `theme/Motion.qml` і зареєструвати singleton** (було 29).  
    **Файли:** `theme/Motion.qml`, `theme/qmldir`.  
    **Дія:** додати ролі тривалостей з точними поточними значеннями: `color 140`, `hover 150`, `press 130`, `scale 140`, `fade 120`, `move 180`, `rotate 320`, `spin 1000`, `popupEnter 180`, `popupExit 120`, `listEnter 180`, `listExit 140`, `osd 180`.  
    **Межі:** цим кроком жодного наявного duration не замінювати; файл поки не використовується.  
    **Перевірка:** reload; візуальних змін немає.

22. **Створити `services/ShellPaths.qml` і зареєструвати singleton** (було 21; доповнення).  
    **Файли:** `services/ShellPaths.qml`, `services/qmldir`.  
    **Дія:** централізувати точні path contracts: `hyprScripts`, `currentTheme`, `colorsJson`, `hyprsunsetState`, `runtimeDir` (з поточним fallback `XDG_RUNTIME_DIR` → `/tmp`), `recordingState`, `clipboardPreviewDir`, `cliphistStore`, `cliphistPreviews` (через `Quickshell.shellPath`).  
    **Межі:** значення шляхів не змінювати.  
    **Перевірка:** reload, PATHS.

23. **Перенести clipboard Python helpers у `scripts/` і усунути абсолютні шляхи launcher** (було 22; доповнення ShellPaths).  
    **Файли:** `cliphist-store.py`, `cliphist-previews.py`, `scripts/`, `launcher/Launcher.qml`.  
    **Дія:** використати `ShellPaths.cliphistStore`/`ShellPaths.cliphistPreviews` з `Quickshell.shellPath("scripts/...")`; передати preview directory в Python як аргумент, зберігши фактичний `/tmp/qs-clip-previews`; QML має одне джерело цього значення — `ShellPaths.clipboardPreviewDir`.  
    **Межі:** команди, формат cliphist і виконавчі біти не змінювати.  
    **Перевірка:** PATHS, LAUNCH, обидва `wl-paste --watch` після повного restart.

24. **Перевести `bar/components/ThemeToggle.qml` на `ShellPaths`** (було 23).  
    **Виконує:** тільки path references.  
    **Перевірка:** THEME.

25. **Перевести `bar/components/RecordingStatus.qml` на `ShellPaths`** (було 24).  
    **Виконує:** тільки шляхи, не анімації/таймери.  
    **Перевірка:** REC.

26. **Перевести `rec/RecordingSetup.qml` на `ShellPaths`** (було 25).  
    **Виконує:** тільки шлях до `screen-record.sh`.  
    **Перевірка:** REC.

27. **Перевести `theme/HyprsunsetService.qml` на `ShellPaths` для state file** (було 26).  
    **Виконує:** ключі JSON і atomic writes не змінювати.  
    **Перевірка:** NIGHT, restart shell.

28. **Перевести `theme/Colors.qml` на `ShellPaths`** (було 27).  
    **Виконує:** після заміни прибрати став непотрібним `home`, якщо він більше ніде не використовується.  
    **Перевірка:** THEME, live reload colors.

29. **Перейменувати `rec/` у `recording/`** (було 28).  
    **Файли:** каталог, `shell.qml`.  
    **Межі:** namespace `recording-setup` не змінювати.  
    **Перевірка:** REC.

30. **Токенізувати `bar/components/Surface.qml`** (було 30).  
    **Виконує:** тільки погоджені Motion/Dimensions tokens.  
    **Межі:** public properties і поточні значення не змінювати.  
    **Перевірка:** BAR, SET, NOTIFY, popup-и.

31. **Токенізувати `bar/components/Pill.qml`** (було 31).  
    **Виконує:** height, padding, spacing та hover/active durations за точним mapping.  
    **Перевірка:** pills, hover scale, active state, довгий text elide.

32. **Токенізувати `bar/components/IconButton.qml`** (було 32).  
    **Виконує:** не змінювати `0.88/1.08`, offsets і mouse behavior.  
    **Перевірка:** settings gear, close buttons, media transport.

33. **Токенізувати `bar/components/ProgressIndicator.qml`** (було 33).  
    **Виконує:** лише повторювані animation tokens.  
    **Межі:** wave math, sampling `0.5`, cycle `1000` і stop indicator не змінювати.  
    **Перевірка:** OSD і bar progress на 0/проміжному/100%.

34. **Іменувати метрики `bar/components/VolumeSlider.qml`** (було 34).  
    **Виконує:** метрики залишаються local readonly, не глобальними; токенізувати лише animation duration.  
    **Перевірка:** drag по краях, wheel step `2`, mute, night-light slider.

35. **Токенізувати `bar/Bar.qml`** (було 35).  
    **Виконує:** gear animation duration може залишитися локальною іменованою константою.  
    **Межі:** `190/120/0.16`, breakpoint `1100`, Workspace offset і masks не змінювати.  
    **Перевірка:** BAR на широкому/вузькому екрані, SET.

36. **Перемістити `settings/Toggle.qml` у `components/`** (було 36).  
    **Файли:** `Toggle.qml`, imports у `InternetPage.qml`, `BluetoothPage.qml`, `BrightnessPopup.qml`.  
    **Межі:** checked/interactive/toggled і animation не змінювати.  
    **Перевірка:** NET, BT, NIGHT.

### Фаза C. Спільні OSD і popup

37. **Створити `osd/OsdPanel.qml` і перевести `VolumeOsd.qml`.**  
    **Дія:** винести однаковий PanelWindow, reveal, timer, pill, gradient і layout; wrapper зберігає service connection та `volumeChangedManually`.  
    **Виконує:** основний агент проєктує API; `qml-mechanic` переносить блоки без зміни значень.  
    **Межі:** `1500ms`, `60px`, `200×36`, namespace `volume-osd` і muted colors не змінювати.  
    **Перевірка:** OSD для mute/0/50/100%.

38. **Перевести `osd/BrightnessOsd.qml` на `OsdPanel`.**  
    **Виконує:** `qml-mechanic` за готовим API.  
    **Межі:** brightness thresholds `<34`, `<67`, namespace `brightness-osd` не змінювати.  
    **Перевірка:** OSD для всіх трьох icon ranges.

39. **Створити `components/AnchoredPopup.qml` і перевести `VolumePopup.qml`.** (доповнення)  
    **Дія:** винести anchor/focus/reveal/Escape/Surface mechanics; wrapper зберігає IPC target `volume`, розміри, header і `controls.refresh()`.  
    **Виконує:** основний агент проєктує API; `qml-mechanic` переносить lifecycle.  
    **Межі:** reveal `180/120`, fallback `40`, translate `8` не змінювати.  
    **Перевірка:** SOUND, outside click, Escape, toggle під час reveal.

40. **Перевести `BrightnessPopup.qml` на `AnchoredPopup`.**  
    **Файли:** `bar/components/BrightnessPopup.qml`.  
    **Виконує:** `qml-mechanic`.  
    **Межі:** IPC target `nightLight`, `refresh()/refreshLocation()`, розміри й header залишаються у wrapper.  
    **Перевірка:** NIGHT, focus grab, outside click, Escape.

41. **Створити `settings/SettingsPageHeader.qml` і перевести Bluetooth.** (доповнення)  
    **Дія:** винести `title`, `topInset`, back button, `46px` header і divider.  
    **Виконує:** основний агент; `qml-mechanic` переносить розмітку.  
    **Перевірка:** BT, back/Escape, top inset.

42. **Перевести Internet на `SettingsPageHeader`.**  
    **Виконує:** `qml-mechanic`; тільки header-блок.  
    **Перевірка:** NET, SET.

### Фаза D. NowPlaying

43. **Винести `bar/components/media/MarqueeText.qml`.**  
    **Виконує:** основний агент; перенести marquee без зміни формул, restart conditions і pause timings.  
    **Перевірка:** MEDIA: короткий/довгий track, collapsed/expanded, hidden player, зміна track під час scrolling.

44. ⏸ **Відкладено, не виконувати.** **Винести `bar/components/media/MprisController.qml`.**  
    **Виконує:** основний агент; зберегти busctl workaround, favicon Process, polling та IPC `nowPlaying`.  
    **Перевірка:** MEDIA, особливо Firefox/Zen stale PlaybackStatus.

### Фаза E. Sound

Кроки 45–47 ⏸ відкладено, не виконувати.

45. ⏸ **Відкладено, не виконувати.** **Винести `bar/components/sound/AudioDeviceCard.qml`.**  
    **Виконує:** основний агент; output/input cards мають використовувати той самий компонент з однаковими візуальними параметрами.  
    **Межі:** settle timers `350ms`, optimistic volume state і codec section не змінювати.  
    **Перевірка:** SOUND: drag/wheel до та після release, unavailable device.

46. ⏸ **Відкладено, не виконувати.** **Винести `bar/components/sound/AudioDeviceList.qml`.**  
    **Виконує:** основний агент; sink/source delegates і поведінка мають бути ідентичні поточним.  
    **Перевірка:** switch default sink/source, counts, active check, empty state, scroll.

47. ⏸ **Відкладено, не виконувати.** **Винести `bar/components/sound/CodecChip.qml`.**  
    **Виконує:** основний агент; `codecLabel()` і A2DP filtering залишити без змін.  
    **Перевірка:** SOUND з Bluetooth headset, active codec disabled, правильний `pactl` profile.

### Фаза F. Settings, notifications, recording

48. **Винести `settings/MainPage.qml` з `SettingsMenu.qml`.**  
    **Виконує:** основний агент; зберегти `revealTick`, staggered animation і signal `open(page)`.  
    **Перевірка:** SET, швидкі повторні open/close, navigation під час reveal.

49. **Винести `notification/NotificationCard.qml`.**  
    **Виконує:** основний агент; NotificationServer і PanelWindow залишаються в `Notification.qml`.  
    **Перевірка:** NOTIFY, кілька карток, stagger, expiry, critical persistence.

50. **Винести `recording/OptionRow.qml`.**  
    **Виконує:** основний агент; previous/next/activated та chip width `190` не змінювати.  
    **Перевірка:** REC, selected row accent, усі п’ять опцій.

51. **Винести `recording/RecordingOptions.qml`.** (доповнення)  
    **Дія:** замінити п’ять паралельних keys/labels/index/cycle-наборів однією data-моделлю з `Repeater`; ownership залишити в `RecordingSetup`.  
    **Виконує:** основний агент.  
    **Перевірка:** REC, усі значення, wrap-around, клавіатура й точна команда `--start`.

### Фаза G. Night Light popup

52. **Винести `bar/components/nightLight/TemperatureCard.qml`.**  
    **Виконує:** основний агент; conversion, rounding, settle timer і presets `2500/4000/6500` не змінювати.  
    **Перевірка:** NIGHT: drag, wheel, presets.

53. **Винести `bar/components/nightLight/ScheduleCard.qml` і `TimeField.qml`.**  
    **Виконує:** основний агент; ModeChip, TimeColumn, steppers, minute step `5`, wrapping `1440` зберегти.  
    **Межі:** open/close popup не змінювати.  
    **Перевірка:** NIGHT: fixed/sun, equal times, invalid location, steppers/wheel.

### Фаза H. Bluetooth

54. **Винести `settings/bluetooth/BluetoothDeviceRow.qml`.**  
    **Виконує:** основний агент; glyph/status mapping передати без зміни результатів.  
    **Перевірка:** BT: battery/delete на hover, connected/pairing/paired, list transitions.

### Фаза I. Internet

55. **Винести `settings/internet/EthernetCard.qml`.**  
    **Виконує:** основний агент; expand/collapse і visibility detail rows не змінювати.  
    **Перевірка:** NET: connected/disconnected/unavailable, довгі DNS/IPv6.

56. **Винести `settings/PasswordField.qml` і `settings/internet/WifiConnectionForm.qml`.** (доповнення)  
    **Виконує:** основний агент; форма володіє submit/cancel, PasswordField — лише полем, visibility icon і key handlers.  
    **Перевірка:** NET: show password, Cancel, Enter/Escape, busy, empty SSID, Open/WPA.

57. **Винести `settings/internet/WifiNetworkRow.qml`.**  
    **Виконує:** основний агент; signal icon, saved/connected labels, hover delete і hit areas зберегти.  
    **Перевірка:** NET: sorting, saved map, connect/disconnect/forget.

58. **Винести `settings/internet/NetworkController.qml`.**  
    **Дія:** перенести стан, сім `Process`, `nmcli` parsing і polling з `InternetPage`; ownership — усередині page.  
    **Виконує:** основний агент; `qml-mechanic` перевіряє кожен внутрішній етап.  
    **Межі:** polling `10000`, refresh delay `200`, `nmcli` commands, escaping і callback order не змінювати.  
    **Перевірка:** повний NET, повторне входження на сторінку, порівняння model до/після.

### Фаза J. Launcher

59. **Винести `launcher/ClipboardController.qml`.**  
    **Виконує:** основний агент; Processes, daemon arguments, модель і preview refresh залишити еквівалентними.  
    **Межі:** controller живе в root Scope, не в PanelWindow.  
    **Перевірка:** LAUNCH, text/image previews, delete/update, daemons після reload.

60. **Винести чисті функції в `launcher/SearchLogic.js`.**  
    **Виконує:** основний агент; scoring `1000/500/350/...`, sorting і regex не змінювати.  
    **Перевірка:** набори запитів до/після, IPC `testSearch`, `^`, `%`, malformed expressions.

61. **Винести `launcher/LauncherResultRow.qml`.**  
    **Виконує:** основний агент; selection, image layout, Enter/mouse actions не змінювати.  
    **Перевірка:** LAUNCH на малому/великому результаті, image metadata, scroll.

### Фаза K. Runtime services

62. **Перемістити `AudioService.qml` у `services/`.**  
    **Файли:** service, `theme/qmldir`, `services/qmldir`, imports у `VolumeOsd.qml`, `Volume.qml`, `SoundControls.qml`.  
    **Виконує:** `qml-mechanic`; реалізацію не змінювати.  
    **Перевірка:** повний shell restart, SOUND, volume keys, external `pactl` updates.

63. **Перемістити `BrightnessService.qml` у `services/`.**  
    **Файли:** service, qmldir, imports у `BrightnessOsd.qml`, `Brightness.qml`, коментар у `ProgressIndicator.qml`.  
    **Виконує:** `qml-mechanic`; `ddcutil` commands/timers не змінювати.  
    **Перевірка:** IPC brightness up/down/set, OSD, monitor-button polling.

64. **Перемістити `HyprsunsetService.qml` у `services/`.**  
    **Файли:** service, qmldir, imports у `Brightness.qml`, `BrightnessPopup.qml`.  
    **Виконує:** `qml-mechanic`; state path і IPC не змінювати.  
    **Перевірка:** NIGHT після restart, state JSON keys.

65. **Винести `services/audio/AudioParser.js`.**  
    **Дія:** чисті `channelList`, `describeDevice`, `deviceIcon`, `parseDevices`, `parseCards`; public API service — через wrappers.  
    **Виконує:** основний агент.  
    **Перевірка:** SOUND, monitor sources filtering, BlueZ array/object profiles.

66. **Винести `services/hyprsunset/Solar.js`.**  
    **Дія:** NOAA sunrise equation без зміни формул.  
    **Виконує:** основний агент.  
    **Перевірка:** sunrise/sunset для тієї ж дати/координат збігаються до хвилини; DST, polar null, різні довготи.

67. **Винести `services/hyprsunset/Schedule.js`.**  
    **Дія:** fixed/sun helpers; mutable state залишається в service.  
    **Виконує:** основний агент.  
    **Перевірка:** overnight/non-overnight, equal times, manual override, startup reconciliation.

68. **Винести `services/hyprsunset/StateStore.qml`.**  
    **Дія:** persistence, atomic writes, load/load-failed ordering і debounce.  
    **Виконує:** основний агент; найризикованіший QML-крок.  
    **Межі:** IPC, location, reconciliation і JSON schema не змінювати.  
    **Перевірка:** NIGHT з коректним, відсутнім і пошкодженим state; restart під час save.

### Фаза L. Hyprland scripts

69. **`set_wallpaper.sh` → `set-wallpaper.sh`.**  
    **Файли:** script, `select_wallpaper.sh`, `random-wallpaper.sh`.  
    **Виконує:** основний агент; `zsh -n`.  
    **Перевірка:** застосування поточного й random wallpaper; awww transition не змінювати.

70. **`select_wallpaper.sh` → `select-wallpaper.sh`.**  
    **Файли:** script, `hyprland.lua`.  
    **Виконує:** основний агент.  
    **Перевірка:** `hyprctl reload`, SUPER+CTRL+T, вибір і Cancel.

71. **`generate_colors.sh` → `generate-colors.sh`.**  
    **Файли:** script, wallpaper scripts, `toggle-theme.sh`, відповідні коментарі `hyprlock.conf`.  
    **Виконує:** основний агент; Matugen options і monitor logic не змінювати.  
    **Перевірка:** THEME, Hyprland/Foot/Neovim/hyprlock outputs.

72. **Винести audio helpers у `screen-record/audio.sh`.**  
    **Дія:** `default_sink_monitor`, `default_microphone`, `wait_for_source`, `setup_audio_mix`, `cleanup_audio_mix`; source через надійно обчислений directory.  
    **Виконує:** основний агент; POSIX `sh`.  
    **Перевірка:** `sh -n`; короткі записи system/mic/both/none; перевірка звуку й вивантаження тимчасових PipeWire modules.

73. **Винести codec/quality helpers у `screen-record/encoders.sh`.**  
    **Дія:** `has_encoder`, `encoder_usable`, `encoder_for`, `quality_bitrate`, `quality_crf`.  
    **Виконує:** основний агент.  
    **Перевірка:** до/після однакові encoder/bitrate/CRF; NVIDIA fallback; короткий запис.

74. **Винести monitor helpers у `screen-record/monitors.sh`.**  
    **Дія:** `detect_fps`, `focused_region`, `focused_monitor_name`.  
    **Виконує:** основний агент.  
    **Перевірка:** full/region recording, auto FPS, `KOLIR_REC_FPS`, відсутність залишкових процесів.

75. **Оновити документацію й виконати фінальний regression pass.**  
    **Файли:** `AGENTS.md`; лише фактично виконана структура.  
    **Виконує:** основний агент; `qml-mechanic` — фінальний QML lint/log check.  
    **Перевірка:** усі коди таблиці; повний restart Quickshell, `hyprctl reload`, IPC smoke tests, FRAME, THEME.

## 8. Поза межами плану

- Виправлення suspect-блоку `hl.window_rule = {...}` у `hyprland.lua`.
- Автоматичне визначення монітора замість `DP-1`.
- Усунення залежності від версії awww cache.
- Перенесення `/tmp/qs-clip-previews` в інший каталог.
- Зміна розташування wallpaper або будь-яких runtime state files.
- Додавання QtTest, тестового framework або інших залежностей.
- Масове перейменування IPC targets або layer namespaces.
- Нормалізація або «покращення» наявних animation timings, spacing, colors і thresholds.
- Перейменування `notification/` у `notifications/`: це дає мало користі й створює зайвий import churn.

## 9. Критерії завершення

- Мертвий код видалено лише після повторного підтвердження відсутності посилань.
- `theme/` містить лише візуальні singletons, `services/` — runtime singletons і path contracts.
- Великі feature-файли розбиті на view/controller/model/helper зі збереженням поточного ownership.
- Спільні OSD, popup, audio cards/lists, settings header і password field не дублюються.
- Повторювані UI-тривалості використовують `Motion` з точними початковими значеннями.
- Відсутні абсолютні `/home/sakura/...` шляхи в QML.
- Відсутні нові QML warnings або runtime errors порівняно з baseline.
- Усі ручні сценарії з таблиці перевірені після повного restart Quickshell і `hyprctl reload`.
