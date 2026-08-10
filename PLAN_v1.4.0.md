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
