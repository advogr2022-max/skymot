# Skymot 1.4.0 — линия регресса

## Цель

Вернуться на **рабочую базу v1.1.0** и заново, аккуратно, добавить нужные фичи — без багов, которые принесли краши в 1.3.0/1.3.1.

## Статус (готово)

| Шаг | Результат |
|---|---|
| Клон | `D:\skymot140` — полный клон `advogr2022-max/skymot` (не sparse) |
| База | `checkout v1.1.0` (commit d1d096a) — **рабочая версия** |
| Ветка | `v1.4.0` (создана от v1.1.0, запушена на GitHub, upstream настроен) |
| Версия | 1.4.0 / code 140 — в `skypuff.pro` + `AndroidManifest.xml` (оба места) |
| Коммит | `c2f8075` — бамп версии |
| **Блок настроек Fast rewind** | ✅ перенесён из 1.3.x (7 настроек, QSettings) — коммит `be730d6` |
| **Фикс чистой сборки** | ✅ `VT_VERSION` как строка в DEFINES (`\\\"1.4.0\\\"`) + `QString::fromUtf8` вместо `number()` — коммит `be730d6` |
| **Фикс краша при старте** | ✅ добавлены недостающие пермишены manifest (ACCESS_NETWORK_STATE и др.) — без них SIGABRT в `ConnectivityManager.getAllNetworkInfo()` — коммит `be730d6` |
| Проверка на AVD | ✅ v1.4.0 установлена, стартует без крашей, блок Fast rewind виден, QSettings-дефолты пишутся |

## ⚠️ Грабли чистой сборки (открыты на 1.4.0)

1. **`-DVT_VERSION=1.4.0` — невалидный float-литерал** (`1.4` + суффикс `.0`): 1.3.x собирались только потому, что `utility.o` не пересобирался (старый от 1.2.0). При чистой сборке — `error: invalid suffix '.0' on floating constant`. Фикс: `DEFINES += VT_VERSION=\\\"$$VT_VERSION\\\"` + в C++ `QString::fromUtf8(VT_VERSION)` вместо `QString::number(VT_VERSION)` (utility.cpp:173,252, boardsetupwindow.cpp:27, mainwindow.cpp:214)
2. **Manifest из v1.1.0 не содержит дефолтных Qt-пермишенов** (ACCESS_NETWORK_STATE, INTERNET, CAMERA, RECORD_AUDIO, BLUETOOTH_ADMIN) — 1.1.0 их получала от androiddeployqt, ручная сборка — нет. Без ACCESS_NETWORK_STATE → **SIGABRT при старте** (`ConnectivityService.getAllNetworkInfo` SecurityException). Сверять с 1.3.x manifest при ручной сборке!
3. **`~/gradle_offline.sh` захардкожен** на `~/build_skypuff` — для 1.4.0 создан `~/gradle_offline140.sh` (путь `~/build_skypuff140/android-build`)

## Что было в v1.1.0 (база)

- Управление лебёдкой VESC: состояния, телеметрия, звук
- Кнопки FAST/SLOW с **настраиваемыми ERPM** (QSettings: `fast_erpm`/`slow_erpm`)
- Экраны: Connection / Skypuff / Config / Terminal
- BLE по адресу (тап по устройству в списке)

## Что НЕ переносим из 1.3.x без разбора

| Фича 1.3.x | Статус | Почему |
|---|---|---|
| **Fast Rewind** (авто-смотка) | ❌ переписать заново | В 1.3.0/1.3.1 привнёс краш при коннекте + ReferenceError frwArmed |
| Файловые логи Download/Skymot | ✅ переносим | Полезно, отдельный модуль (main.cpp logGeneral/logSmot) |
| QML↔C++ фиксы (drawnMeters, postStatus) | ✅ переносим | Правильные API, не связаны с крашем |

## Правила работы в 1.4.0

1. **Одна фича = один коммит**, после каждого — проверка на эмуляторе (0 ошибок в логе)
2. **QML-property только на корне Page** (урок v1.3.2 — иначе ReferenceError в binding'ах)
3. **Прошивку VESC не трогаем** — всё на стороне APK
4. **`si_motor_poles` держать 6** — APK перезаписывает при Send (UI дефолт 32!)
5. Перед переносом кода из 1.3.x — diff-ревью: что именно менялось, зачем

## План (черновик)

- [x] База 1.1.0 + ветка v1.4.0 + версия
- [ ] Проверка сборки из новой папки (`/mnt/d/skymot140/...`) — qmake + make + gradle
- [ ] Быстрый тест базы на AVD (убедиться, что 1.4.0 = 1.1.0 по поведению)
- [ ] Перенос: файловые логи (главный инструмент диагностики)
- [ ] Перенос: QML↔C++ API-фиксы (drawnMeters/postStatus)
- [ ] Fast Rewind — редизайн: сначала причина краша при коннекте, потом фича
- [ ] Полевой тест у инженера

## Сборка (напоминание, путь новый)

```bash
cd ~/build_skypuff140   # новая build-папка в WSL
/home/user/Qt/5.15.2/android/bin/qmake ANDROID_ABIS="arm64-v8a" \
  /mnt/d/skymot140/application/skymot/skypuff.pro
make -j8 && cp libskypuff_arm64-v8a.so android-build/libs/arm64-v8a/
bash ~/gradle_offline.sh
cp android-build/build/outputs/apk/debug/android-build-debug.apk /mnt/d/skymot140/Skymot-1.4.0.apk
```
