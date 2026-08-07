# Skymot APK 1.1.0 — чеклист обновления для заказчика

Дата: 07.08.2026
Версия APK: **1.1.0** (пакет `skymot.winch`, versionCode 110)
Что это: обновление приложения управления лебёдкой (исходная база SkyPuff 4.00 / v6.05 ddosoff)

---

## 1. Зачем (кратко)

В APK добавлены **две тестовые кнопки управления мотором** для проверки лебёдки
на земле (без пилота на тросе), исправлены ошибки запуска (белый экран) и
настроена сборка с полным набором QML-модулей Qt. В v1.1.0 добавлены
**настройки скоростей кнопок FAST/SLOW** прямо в приложении (экран настроек).
Прошивка VESC **не изменялась**.

## 2. Что именно сделано (чеклист изменений)

| # | Что изменено | Детали |
|---|---|---|
| 1 | Исправлен краш при запуске (белый экран) | В `PageSkypuff.qml` добавлены импорты `Vedder.vesc.vescinterface`, `Vedder.vesc.commands`, `Vedder.vesc.configparams` и объявление `property ConfigParams cfg` — без них вызовы команд падали с `ReferenceError: VescIf is not defined` |
| 2 | Доставлены QML-модули Qt | В тулчейн установлены `QtQuick.Controls` (1.4), `QtQuick.Extras`, `QtQuick.Dialogs`, `QtQuick.PrivateWidgets` — без них QML-страницы не грузились (краш) |
| 3 | Кнопка **FAST** (красная, 100x100) | Нажата: команда `COMM_SET_RPM fastErpm()` (по умолчанию 20000 ERPM, повтор каждые 100 мс). Если трос идёт легко — ток малый. При токе > 150 А — переключение на удержание тока 150 А (`COMM_SET_CURRENT 150`). При разгоне выше заданных ERPM в режиме тока — возврат в скоростной режим (VESC снижает ток). Отпущена: `COMM_SET_CURRENT 0` |
| 4 | Кнопка **SLOW** (зелёная, 100x100) | Нажата: `COMM_SET_RPM slowErpm()` (по умолчанию 3000 ERPM, повтор каждые 100 мс). При токе > 150 А — аварийная остановка (`COMM_SET_CURRENT 0`, кнопка гаснет). Отпущена: стоп |
| 5 | Блокировка кнопок по состоянию лебёдки | Кнопки активны в: `UNINITIALIZED`, `MANUAL_BRAKING`, `MANUAL_SLOW*`, `UNWINDING`, `REWINDING`, `DISCONNECTED`. Заблокированы (серые) в: `PULL`, `TAKEOFF`, `PRE_PULL`, `SLOWING`, `BRAKING`, `BRAKING_EXTENSION` — чтобы исключить конфликт команд с автоматикой (пилот на тросе) |
| 6 | Диагностические логи | Были добавлены в `Commands::setCurrent/setRpm` (logcat: `CMD_SET_CURRENT`/`CMD_SET_RPM`) для отладки. **В финальной версии 1.0.3 удалены** — logcat чистый, на работу/производительность не влияет |
| 7 | Пакет/версия | Пакет переименован `skypuff.winch` → `skymot.winch`, versionCode 110, minSdk 26 (Android 8+), targetSdk 34 |
| 8 | Архитектуры | **Только arm64-v8a** (native-code), размер APK **~26 МБ** (< 30 МБ) — целевые устройства — современные Android-смартфоны |
| 9 | Настройки ERPM кнопок (новое в 1.1.0) | Внизу экрана настроек группа **"Test buttons (ERPM)"**: `FAST button ERPM` и `SLOW button ERPM`, диапазон **100–50000**, шаг 500. Сохраняются на смартфоне сразу при изменении; на VESC не отправляются |

**Прошивка VESC: не изменялась.** В репозитории прошивки остаются только ранее
согласованные правки (лимит rewinding 150 А, A/KG 4.54, max_speed 39 м/с) —
они не входят в этот апдейт APK.

## 3. Требования к окружению для повторной сборки

Сборка выполняется в **WSL (Ubuntu)** на Windows-машине:

| Компонент | Версия / путь в WSL | Примечание |
|---|---|---|
| Qt (aqt-сборка) | `~/Qt/5.15.2/android` | Обязательно с доустановленным `qtquickcontrols` (см. п. 4.1) |
| Android NDK | `~/Android/Sdk/ndk/23.1.7779620` | Точно как в оригинале |
| Android SDK | `~/Android/Sdk` (build-tools 28.0.3) | Для aapt2 |
| JDK | `~/jdk11` (Java 11) | Gradle 5.6.4 не работает на более новых |
| Gradle | 5.6.4 (wrapper, offline) | Кэш `~/.gradle/wrapper/dists/gradle-5.6.4-bin/bxirm19lnfz6nurbatndyydux` |
| Локальный maven-репозиторий | `~/m2repo` | Содержит gradle 3.2.0, aapt2 3.2.0-4818971 (linux) |
| Исходники приложения | `D:\skymot\vesc_tool_src\application\skypuff` | Ветка/копия с правками |
| Директория сборки | `~/build_skypuff` (в WSL) | qmake + make + androiddeployqt работают здесь |

## 4. Чеклист повторной сборки

### 4.1. Если тулчейн ставится с нуля

```bash
# Qt 5.15.2 android (aqtinstall), все модули:
aqt install-qt linux android 5.15.2 --arch android_arm64_v8a \
    --modules qtquickcontrols2 qtmultimedia qtsvg qtconnectivity qtpositioning \
    qtserialport qtserialbus qtgamepad qtquickcontrols
# ВАЖНО: модуль qtquickcontrols (QtQuick.Controls 1.4 / Extras / Dialogs)
# не входит в базовый aqt-пакет для android — его архив качается отдельно:
#   https://download.qt.io/online/qtsdkrepository/linux_x64/android/qt5_5152/
#   qt.qt5.5152.android/5.15.2-0-202011130628qtquickcontrols-...Multi.7z
# распаковать в ~/Qt/5.15.2/android/ (структура 5.15.2/android/qml/QtQuick/...)
```

### 4.2. Сборка библиотеки (в WSL, arm64-v8a)

```bash
export ANDROID_HOME=/home/user/Android/Sdk
export ANDROID_NDK_ROOT=/home/user/Android/Sdk/ndk/23.1.7779620
export JAVA_HOME=/home/user/jdk11
export PATH="$JAVA_HOME/bin:/home/user/Android/Sdk/ndk/23.1.7779620/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"

cd ~/build_skypuff
# ВАЖНО: ANDROID_ABIS="arm64-v8a" ограничивает сборку одной архитектурой
# (иначе qmake перезапишет deployment settings на все 4 ABI)
/home/user/Qt/5.15.2/android/bin/qmake ANDROID_ABIS="arm64-v8a" \
    /mnt/d/skymot/vesc_tool_src/application/skypuff/skypuff.pro
make -j8
# Результат: ~/build_skypuff/libskypuff_arm64-v8a.so
```

### 4.3. Сборка APK (androiddeployqt + gradle offline)

```bash
cd ~/build_skypuff
# 0. После qmake проверить/исправить путь SDK в deployment settings:
#    sed -i 's|/opt/android/sdk|/home/user/Android/Sdk|' android-skypuff-deployment-settings.json
#    (qmake при перегенерации сбрасывает его на /opt/android/sdk)

# 1. androiddeployqt. Падение с "Cannot find application binary ... libskypuff_X.so"
#    с кодом 2 — ОЖИДАЕМО (см. шаг 2), не ошибка:
/home/user/Qt/5.15.2/android/bin/androiddeployqt \
    --input android-skypuff-deployment-settings.json --output android-build

# 2. Разложить .so приложения в android-build/libs (иначе gradle не соберёт):
mkdir -p android-build/libs/arm64-v8a
cp libskypuff_arm64-v8a.so android-build/libs/arm64-v8a/libskypuff_arm64-v8a.so

# 3. ПОВТОРИТЬ androiddeployqt (первый запуск падает на шаге 1 ДО копирования
#    android-пакета: build.gradle/AndroidManifest). Второй запуск доходит до gradle.
#    Если androiddeployqt внутри завис на gradle (нет сети) — прервать (Ctrl+C),
#    gradle запускается отдельно (шаг 4).
/home/user/Qt/5.15.2/android/bin/androiddeployqt \
    --input android-skypuff-deployment-settings.json --output android-build

# 4. Добавить локальный m2repo в build.gradle (если сброшен androiddeployqt'ом):
#    в buildscript.repositories и repositories первой строкой:
#    maven { url 'file:///home/user/m2repo' }

# 5. Сборка gradle (офлайн! WSL без интернета):
cd android-build
/home/user/.gradle/wrapper/dists/gradle-5.6.4-bin/bxirm19lnfz6nurbatndyydux/gradle-5.6.4/bin/gradle \
    assembleDebug --offline --no-daemon
# Результат: build/outputs/apk/debug/android-build-debug.apk
```

**Известные грабли (обязательно проверить):**
- `~/m2repo/com/android/tools/build/aapt2/3.2.0-4818971/` должен содержать
  `aapt2-3.2.0-4818971-linux.jar` — без него gradle падает
  `Could not resolve com.android.tools.build:aapt2` (WSL без сети не скачает).
  Источник: `https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/3.2.0-4818971/aapt2-3.2.0-4818971-linux.jar`
- `android-skypuff-deployment-settings.json` должен содержать
  `"sdk": "/home/user/Android/Sdk"` (не `/opt/android/sdk`).
- androiddeployqt внутри сам запускает gradle — в офлайн-WSL он **зависает**
  на скачивании зависимостей. Поэтому gradle запускается отдельно (шаг 4).

### 4.4. Финальный APK

```bash
cp ~/build_skypuff/android-build/build/outputs/apk/debug/android-build-debug.apk \
   /mnt/d/skymot/Skymot-1.1.0.apk
```

Проверка метаданных (aapt из build-tools 28.0.3):
```
package: name='skymot.winch' versionCode='110' versionName='1.1.0'
sdkVersion:'26'
native-code: 'arm64-v8a'
```

## 5. Чеклист установки и проверки

### 5.1. Установка на телефон (Android 8+)

1. Скопировать `Skymot-1.1.0.apk` на телефон.
2. Разрешить установку из неизвестных источников.
3. Установить. Приложение появится как **Skymot** (иконка рядом с оригиналом SkyPuff 4.00 — оба работают независимо, пакеты разные).

### 5.2. Быстрая проверка в эмуляторе (опционально)

```bash
# Официальный AVD (API 30, x86_64):
D:\Android\Sdk\emulator\emulator.exe -avd skymot -gpu swiftshader_indirect -no-snapshot -no-boot-anim -no-audio
adb -s emulator-5556 install -r D:\\skymot\\Skymot-1.1.0.apk
adb -s emulator-5556 shell am start -n skymot.winch/org.qtproject.qt5.android.bindings.QtActivity
# Поток команд при нажатии кнопок (нужен реальный VESC по BLE для приёма):
adb -s emulator-5556 shell logcat -d | grep -E "CMD_SET"
```

### 5.3. Проверка на реальном железе (обязательно, трос снят!)

1. Подключить телефон к VESC по BLE (страница Connection).
2. Убедиться, что лебёдка в состоянии `UNINITIALIZED` (после включения) — кнопки активны.
3. **FAST** (красная): нажать — мотор набирает обороты до заданных ERPM
   (по умолчанию 20000 ≈ 38.8 м/с при poles=6, D=200 мм, gear=1.8). Лёгкий ход — ток малый.
   Затормозить барабан рукой — ток растёт до ~150 А и держится (тяга ~33 кгс),
   скорость не превышает заданные ERPM. Отпустить — мотор стоп.
4. **SLOW** (зелёная): нажать — мотор крутит заданные ERPM
   (по умолчанию 3000 ≈ 5.8 м/с).
   Затормозить — при токе > 150 А автоматический стоп.
5. **Настройка скоростей**: экран настроек (иконка шестерёнки) → внизу группа
   "Test buttons (ERPM)" → задать FAST/SLOW ERPM (100–50000) → вернуться на
   главный экран и проверить кнопки. Значения сохраняются на смартфоне,
   переживают перезапуск приложения.
6. Проверить на главном экране: метраж (шкала троса), кг (тяга), скорость
   обновляются при нажатиях.
7. В logcat (или по телеметрии) убедиться в потоке команд:
   `CMD_SET_RPM <заданные ERPM>` каждые ~100 мс при удержании, `CMD_SET_CURRENT 0` при отпускании.

### 5.4. Ограничения (важно донести до пользователя)

- Кнопки **заблокированы** в режимах `PULL`, `TAKEOFF`, `SLOWING`, `BRAKING` —
  это защита от конфликта с автоматикой (пилот на тросе). Для тестов мотора
  используйте состояния `UNINITIALIZED` / ручные режимы / `UNWINDING`/`REWINDING`.
- В `UNWINDING`/`REWINDING` прошивка может кратковременно вмешаться в управление
  в моменты своих событий (смена зоны, триггеры длины) — это нормально.
- 20000 ERPM ≈ 38.8 м/с (по умолчанию) — проверяйте только с тросом, уложенным на земле.
- Прошивка VESC для работы override-логики НЕ требуется — всё реализовано в APK.

## 6. Файлы, затронутые правками (для контроля версий)

| Файл | Правки |
|---|---|
| `vesc_tool_src/application/skypuff/res/PageSkypuff.qml` | Кнопки FAST/SLOW 100x100, логика гибрида 150 А, блокировка по состояниям, импорты VescIf/commands/configparams, `property cfg`; v1.1.0: ERPM читаются из настроек (`Skypuff.fastErpm()`/`slowErpm()`) вместо хардкода |
| `vesc_tool_src/application/skypuff/res/PageConfig.qml` | (v1.1.0) Группа "Test buttons (ERPM)" внизу экрана настроек — поля FAST/SLOW ERPM 100–50000 |
| `vesc_tool_src/application/skypuff/skypuff.h/.cpp` | (v1.1.0) Методы `fastErpm()/setFastErpm()/slowErpm()/setSlowErpm()` — хранение в QSettings смартфона (ключи `skypuff/fast_erpm`, `skypuff/slow_erpm`, дефолты 20000/3000) |
| `vesc_tool_src/application/skypuff/skypuff.pro` | Версия 1.1.0, versionCode 110 |
| `vesc_tool_src/application/skypuff/android/AndroidManifest.xml(.in)` | minSdk 26 (Android 8), версия 1.1.0 |
| `~/Qt/5.15.2/android/qml/QtQuick/{Controls,Dialogs,Extras,PrivateWidgets}` | Доустановленный модуль qtquickcontrols (вне репозитория — в тулчейне!) |

**Важно:** модуль qtquickcontrols живёт в тулчейне (`~/Qt/5.15.2/android/qml/`),
а не в репозитории проекта — при переносе на другую машину его нужно
доустановить (п. 4.1), иначе APK соберётся без модулей и приложение упадёт
при запуске (белый экран).

## 7. Откат

Установить предыдущий APK (например, оригинальный SkyPuff 4.00 — пакет
`skypuff.winch`, они сосуществуют). Правки в APK не затрагивают прошивку VESC
и её конфигурацию.
