# Skymot — VESC Winch Controller (Android)

Приложение управления электрической лебёдкой на базе VESC.
**Дочернее приложение от `application/skypuff`** (ddosoff/vesc_tool) со всеми
доработками. Пакет: `skymot.winch`, версия **1.1.0**.

> APK для установки и полная инструкция по повторной сборке — в **Releases**
> этого репозитория (файл `Skymot-1.1.0.apk` + `upgrade.md`).

---

## Отличия от application/skypuff (все правки с комментариями)

### 1. `res/PageSkypuff.qml` — тестовые кнопки управления мотором

Добавлены две круглые кнопки 100x100 по бокам от блока батареи:

| Кнопка | Цвет | Действие |
|---|---|---|
| **FAST** (красная) | `#D32F2F` | Нажата: `COMM_SET_RPM fastErpm()` (по умолчанию 20000 ERPM, повтор каждые 100 мс). Трос идёт легко — ток малый. Ток > 150 А — переключение на удержание `COMM_SET_CURRENT 150`. Разгон выше заданных ERPM в режиме тока — возврат в скоростной режим (VESC сам снижает ток). Отпущена: `COMM_SET_CURRENT 0` |
| **SLOW** (зелёная) | `#388E3C` | Нажата: `COMM_SET_RPM slowErpm()` (по умолчанию 3000 ERPM, повтор каждые 100 мс). Ток > 150 А — аварийный стоп. Отпущена: стоп |

- Повтор команд каждые 100 мс таймером (`tRedRepeat`/`tGreenRepeat`) — заодно
  сбрасывает штатный таймаут VESC (при потере BLE мотор сам остановится через
  App Settings → Timeout).
- **Защита FAST**: `fastCurrentMode` — при токе > 150 А приложение переходит
  в режим удержания тока 150 А; при спаде < 140 А (гистерезис) или разгоне
  выше заданных ERPM (`msToErpm()` по конфигу: poles/gear/D) возвращается в RPM.
- **Блокировка по состоянию лебёдки** (`enabled`): кнопки активны только в
  состояниях, где прошивка не пишет мотор в steady state — `UNINITIALIZED`,
  `MANUAL_*`, `UNWINDING`, `REWINDING`, `DISCONNECTED`. Заблокированы в
  `PULL`/`TAKEOFF`/`SLOWING`/`BRAKING` — защита от конфликта команд с
  автоматикой (пилот на тросе).

### 2. `res/PageSkypuff.qml` — исправление краша при запуске

Добавлены импорты модулей `Vedder.vesc.vescinterface`, `Vedder.vesc.commands`,
`Vedder.vesc.configparams` и объявление
`property ConfigParams cfg: VescIf.appConfig()`.
Без них вызовы кнопок падали с `ReferenceError: VescIf is not defined`
(белый экран при нажатии).

### 3. `android/AndroidManifest.xml(.in)` — пакет, версия, Android 8+

- Пакет: `skypuff.winch` → **`skymot.winch`**
- `versionName` 1.1.0, `versionCode` 110
- `minSdkVersion` **26** (Android 8+), `targetSdkVersion` 34
- Label Activity: `Skymot-$$VT_VERSION` (автоматически подставляется версия
  из `skypuff.pro`; раньше был захардкожен и отставал от версии APK)

### 4. `skypuff.pro` — версия

`VT_VERSION = 1.1.0`, коды Android-версий 110. Сборка целевая — **arm64-v8a**
(см. `qmake ANDROID_ABIS="arm64-v8a"` в инструкции; размер APK ~26 МБ).

### 5. Настройки ERPM кнопок FAST/SLOW (v1.1.0)

- `res/PageConfig.qml` — внизу экрана настроек группа **"Test buttons (ERPM)"**:
  два поля `FAST button ERPM` и `SLOW button ERPM`, диапазон **100–50000**,
  шаг 500, сохраняются сразу при изменении.
- `skypuff.h/.cpp` — методы `fastErpm()/setFastErpm()/slowErpm()/setSlowErpm()`
  (QSettings, ключи `skypuff/fast_erpm`, `skypuff/slow_erpm`). **При первом
  запуске приложения дефолты 20000/3000 записываются в конфиг смартфона** —
  при чистой установке кнопки сразу работают на заводских значениях.
- `res/PageSkypuff.qml` — кнопки читают значения из настроек вместо хардкода.
- **Значения хранятся только на смартфоне** — на VESC не отправляются
  (прошивка их не знает, `serializeV1` не менялся — протокол с прошивкой
  полностью совместим).

---

## Требования к тулчейну

Сборка Android APK (Qt 5.15.2 + NDK 23.1.7779620 + JDK 11 + gradle 5.6.4
offline) в WSL — **полный чеклист в `upgrade.md` релиза**. Ключевые пункты:

1. Qt 5.15.2 android **обязательно с модулем `qtquickcontrols`**
   (QtQuick.Controls 1.4 / Extras / Dialogs / PrivateWidgets) — без него
   приложение падает при запуске (белый экран). Модуль доустанавливается
   отдельно в `~/Qt/5.15.2/android/qml/QtQuick/`.
2. `qmake ANDROID_ABIS="arm64-v8a"` — сборка только под arm64.
3. После qmake поправить `android-skypuff-deployment-settings.json`:
   `"sdk": "/home/user/Android/Sdk"` (qmake сбрасывает на `/opt/android/sdk`).
4. androiddeployqt запускать дважды (первый падает до копирования
   android-пакета — норм), затем gradle `assembleDebug --offline --no-daemon`.

---

## Ограничения

- Кнопки FAST/SLOW — тестовые: только при тросе, уложенном на земле
  (дефолтные 20000 ERPM ≈ 38.8 м/с при poles=6, D=200 мм, gear=1.8).
- В `UNWINDING`/`REWINDING` прошивка может кратковременно вмешаться в
  управление в моменты своих событий (смена зоны, триггеры длины) — норма.
- Прошивка VESC **не изменялась** — всё реализовано на стороне APK.
