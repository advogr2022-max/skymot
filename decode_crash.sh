#!/bin/bash
# Расшифровка crash.log инженера → функция + файл:строка
# Использование: bash decode_crash.sh <crash.log> [<libskypuff.so>]
#   libskypuff.so по умолчанию берётся из APK Skymot-1.4.1-crashdbg.apk
set -e

CRASH_LOG="$1"
SO="${2:-}"
if [ -z "$SO" ]; then
    SO="/tmp/libskypuff_g.so"
    if [ ! -f "$SO" ]; then
        python3 -c "
import zipfile
z = zipfile.ZipFile('/mnt/d/skymot140/Skymot-1.4.1-crashdbg.apk')
open('$SO','wb').write(z.read('lib/arm64-v8a/libskypuff_arm64-v8a.so'))
"
    fi
fi

export PATH=/home/user/Android/Sdk/ndk/23.1.7779620/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
SYM=llvm-symbolizer

echo "=== breadcrumbs ==="
awk '/--- last steps ---/{f=1;next} /--- backtrace/{f=0} f' "$CRASH_LOG"

echo
echo "=== backtrace PCs (расшифровка) ==="
# база libskypuff из maps: первая строка с libskypuff, начало диапазона
BASE=$(grep -m1 'libskypuff_arm64-v8a.so' "$CRASH_LOG" | tr -d '\r' | awk '{print $1}' | cut -d- -f1)
if [ -n "$BASE" ] && [ "${BASE:0:2}" != "0x" ]; then
    BASE="0x$BASE"
fi
if [ -z "$BASE" ]; then
    echo "!! база .so не найдена в crash.log (maps пуст?) — нужен адрес вручную"
    BASE=0
fi
echo "база загрузки libskypuff: $BASE"

awk '/--- backtrace PCs ---/{f=1;next} /--- \/proc/{f=0} f' "$CRASH_LOG" | tr -d '\r' | while read -r pc; do
    [ -z "$pc" ] && continue
    [ "$pc" = "0x0" ] && continue
    off=$((pc - BASE))
    printf '  PC %s -> offset 0x%x\n' "$pc" "$off"
    printf '0x%x\n' "$off" | $SYM --obj="$SO" | sed 's/^/      /'
done
