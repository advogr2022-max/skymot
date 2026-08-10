import QtQuick 2.12
import QtQuick.Dialogs 1.2
import QtQuick.Controls 2.2
import QtQuick.Extras 1.4
import QtQuick.Layouts 1.12
import QtQuick.Controls.Material 2.12
import QtGraphicalEffects 1.0

import Vedder.vesc.vescinterface 1.0
import Vedder.vesc.commands 1.0
import Vedder.vesc.configparams 1.0

import SkyPuff.vesc.winch 1.0

Page {
    id: page
    property ConfigParams cfg: VescIf.appConfig()

    // ===== Fast Rewind (auto rewind override) state =====
    property bool fastCurrentMode: false  // красная кнопка: true = держим ток 150А (перегрузка)
    property bool frwRunning: false      // авто-таймер активен
    property bool frwSlowPhase: false    // медленная фаза (последние метры)
    property bool frwStopped: false      // стоп до следующего цикла REWINDING (зацеп/кнопка Стоп)
    property bool frwCurrentMode: false  // true = держим ток (перегрузка)
    property int frwErpmNow: 0           // текущий задаваемый ERPM (плавно меняется)
    property int frwRampStart: 0         // ERPM в начале лестницы
    property int frwRampTarget: 0        // целевой ERPM лестницы
    property int frwRampTick: 10         // текущий тик лестницы (10 = готово)
    property int frwRampTicksTotal: 10   // тиков на лестницу (Ramp time)
    property real frwLastPos: 0          // последняя позиция (детект зацепа)
    property int frwStallTicks: 0        // тики без движения

    // Плавная смена целевого ERPM: линейная лестница от текущего к новому
    function frwSetTarget(t) {
        if (t === frwRampTarget && frwRampTick < frwRampTicksTotal) return
        frwRampStart = frwErpmNow
        frwRampTarget = t
        frwRampTick = 0
        frwRampTicksTotal = Math.max(3, Math.round(Skypuff.rewindRamp() * 10))
    }

    // ===== Плавный разгон/торможение ручных кнопок FAST/SLOW =====
    // Те же настройки с экрана настроек: fast_erpm/slow_erpm + Ramp time (rewind_ramp)
    property int btnErpmNow: 0          // текущий задаваемый ERPM
    property int btnRampStart: 0        // ERPM в начале лестницы
    property int btnRampTarget: 0       // целевой ERPM
    property int btnRampTick: 10        // текущий тик (10 = готово)
    property int btnRampTicksTotal: 10  // тиков на лестницу (Ramp time)
    property bool btnRamping: false     // лестница активна (разгон или торможение)

    function btnSetTarget(t) {
        btnRampStart = btnErpmNow
        btnRampTarget = t
        btnRampTick = 0
        btnRampTicksTotal = Math.max(3, Math.round(Skypuff.rewindRamp() * 10))
        btnRamping = true
    }

    // скорость троса (м/с) → ERPM мотора
    function msToErpm(ms) {
        var mpr = (cfg.wheel_diameter_mm / 1000) / cfg.gear_ratio * Math.PI; // м на оборот вала
        return (ms / mpr * 60) * (cfg.motor_poles / 2);
    }
    state: "DISCONNECTED"

    property string bgGreenColor: '#A5D6A7'
    property string bgBlueColor: '#90CAF9'
    property string bgRedColor: '#EF9A9A'
    property string bgYellowColor: '#FFE082'

    property real bFontSize: Math.max(page.width * 0.04, 10)
    property real bHeight: Math.max(page.width * 0.17, 10)
    property real kgValFontSize: Math.max(page.width * 0.04, 10)

    // Get normal text color from this palette
    SystemPalette {id: systemPalette; colorGroup: SystemPalette.Active}

    // Confirm Set Zero Here
    Popup {
        id: confirmResetZero
        modal: true
        anchors.centerIn: parent
        contentWidth: parent.width - 50

        ColumnLayout {
            anchors.fill: parent

            Label {
                Layout.margins: 10
                text: qsTr('Set zero here')
                font.bold: true
            }

            Text {
                Layout.margins: 10
                Layout.fillWidth: true
                elide: Text.ElideMiddle
                wrapMode: Text.WordWrap
                text: qsTr("Reset rope position?")
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.margins: 20
                Button {
                    text: qsTr('Yes')
                    onClicked: {
                        confirmResetZero.close()
                        Skypuff.sendTerminal("set_zero");
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                Button {
                    text: qsTr('No')
                    onClicked: confirmResetZero.close()
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent

        RowLayout {
            spacing: 0

            BigRoundButton {
                id: bCut
                enabled: true
                radius: 0

                text: qsTr("Cut")
                font.pixelSize: page.bFontSize
                Layout.preferredHeight: page.bHeight
                Layout.fillWidth: true
                Layout.preferredWidth: page.width / 10
                background.anchors.fill: bCut
                Material.background: page.bgRedColor

                onClicked: {Skypuff.sendTerminal("guillotine")}
            }

            BigRoundButton {
                id: bStop
                enabled: false
                radius: 0

                text: qsTr("Stop")
                font.pixelSize: page.bFontSize
                Layout.preferredHeight: page.bHeight
                Layout.fillWidth: true
                background.anchors.fill: bStop
                Material.background: page.bgYellowColor

                CustomBorder {
                    visible: parent.enabled
                    commonBorder: false
                    lBorderwidth: 1
                    rBorderwidth: 0
                    tBorderwidth: 0
                    bBorderwidth: 0
                    borderColor: Qt.darker(page.bgYellowColor, 1.2)
                }

                onClicked: {
                    // В режиме смотки: аварийный стоп — глушим Fast Rewind,
                    // мгновенно снимаем ток, затем штатный переход в удержание
                    if (["REWINDING", "SLOWING", "SLOW"].indexOf(Skypuff.state) !== -1) {
                        frwStopped = true
                        frwRunning = false
                        frwCurrentMode = false
                        frwErpmNow = 0
                        VescIf.commands().setCurrent(0)
                    }
                    Skypuff.sendTerminal("set MANUAL_BRAKING")
                }
            }
        }

        /*Label {
            visible: true
            id: lState
            text: Skypuff.stateText

            Layout.fillWidth: true
            Layout.topMargin: 10
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: 16
            font.bold: true

            color: page.state === "MANUAL_BRAKING" ? "red" : systemPalette.text;
        }*/

        // Status messages from skymot with normal text color
        // or blinking faults
        /*Text {
            id: tStatus
            visible: true
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter

            SequentialAnimation on color {
                id: faultsBlinker
                loops: Animation.Infinite
                ColorAnimation { easing.type: Easing.OutExpo; from: systemPalette.window; to: "red"; duration: 400 }
                ColorAnimation { easing.type: Easing.OutExpo; from: "red"; to: systemPalette.window;  duration: 200 }
            }

            Timer {
                id: statusCleaner
                interval: 5 * 1000

                onTriggered: {
                    tStatus.text = Skypuff.fault

                    if(Skypuff.fault)
                        faultsBlinker.start()
                    else
                        faultsBlinker.stop()
                }
            }

            Connections {
                target: Skypuff

                onStatusChanged: {
                    tStatus.text = newStatus
                    tStatus.color = isWarning ? "red" : systemPalette.text

                    statusCleaner.restart()
                    faultsBlinker.stop()
                }

                onFaultChanged:  {
                    if(newFault) {
                        tStatus.text = newFault
                        faultsBlinker.start()
                    }
                    else
                        statusCleaner.restart()
                }
            }
        }*/

        SkypuffGauge {
            id: sGauge

            rootDiameter: page.width

            smallDimension: true // отключи, если изменение скорости или веревки слишком грузит цпу

            paddingLeft: 10
            paddingRight: 10
            marginTop: 15
            //maxRopeMeters: 20

            // Temps
            tempFets: Skypuff.tempFets
            tempMotor: Skypuff.tempMotor

            // Statuses
            stateText: Skypuff.stateText
            status: Skypuff.fault

            Connections {
                target: Skypuff

                //onMotorModeChanged: { sGauge.motorMode = Skypuff.motorMode; }
                onMotorKgChanged: { sGauge.motorKg = Math.abs(Skypuff.motorKg); }
                onSpeedMsChanged: { sGauge.speedMs = Skypuff.speedMs; }
                onPowerChanged: { sGauge.power = Skypuff.power; }

                onLeftMetersChanged: { sGauge.leftRopeMeters = Skypuff.leftMeters.toFixed(1); }
                onDrawnMetersChanged: { sGauge.ropeMeters = Skypuff.drawnMeters; }
                onRopeMetersChanged: { sGauge.maxRopeMeters = Skypuff.ropeMeters.toFixed(); }

                // Warning and Blink (bool) | I don't know names of this params
                //onIsMotorKgWarningChanged: { sGauge.isMotorKgWarning = false; } // Warning
                //onIsMotorKgBlinkingChanged: { sGauge.isMotorKgBlinking = false; } // Blink

                //onIsRopeWarningChanged: { sGauge.isRopeWarning = false; }
                //onIsRopeBlinkingChanged: { sGauge.isRopeBlinking = false; }

                //onIsPowerWarningChanged: { sGauge.isPowerWarning = false; }
                //onIsPowerBlinkingChanged: { sGauge.ispowerBlinking = false; }

                //onIsSpeedWarningChanged: { sGauge.isSpeedWarning = false; }
                //onIsSpeedBlinkingChanged: { sGauge.isSpeedBlinking = false; }

                //onIsTempBatteryWarningChanged: { sGauge.isTempBatteryWarning = false; }
                //onIsTempMcuWarningChanged: { sGauge.isTempMcuWarning = false; }
                //onIsTempMotorWarningChanged: { sGauge.isTempMotorWarning = false; }

                onSettingsChanged: {
                    sGauge.maxMotorKg = cfg.motor_max_kg;
                    sGauge.maxPower = cfg.power_max;
                    sGauge.minPower = cfg.power_min;
                    sGauge.maxSpeedMs = cfg.max_speed_ms;
                }

                onStateChanged: {
                    sGauge.state = newState;
                }

                onStatusChanged: {
                    sGauge.status = newStatus;
                    sGauge.isWarningStatus = isWarning;
                }

                onFaultChanged:  {
                    if(newFault) {
                        sGauge.status = newFault;
                    }

                }
            }

            // Индикатор Fast Rewind: серый — неактивен, красный — ускоренная смотка работает.
            // В центре круга прибора, между шкалами кг и ватт. Размер — вдвое меньше кнопки SLOW.
            Rectangle {
                id: frwIndicator
                width: 50
                height: 50
                radius: 25
                z: 10
                color: frwRunning ? "#D32F2F" : "#9E9E9E"
                border.color: "white"
                border.width: 2
                anchors.centerIn: parent
                Behavior on color { ColorAnimation { duration: 200 } }
            }
        }

        RowLayout {
            Layout.topMargin: 15

            // ===== TEST: красная кнопка FAST — Skypuff.fastErpm() ERPM (настройка), при перегрузке держит ток 150А =====
            RoundButton {
                id: rTestCurrent
                Layout.topMargin: -5
                Layout.leftMargin: 5
                text: "FAST"
                implicitWidth: 100
                implicitHeight: 100
                font.pixelSize: 20
                Material.background: "#D32F2F"
                Material.foreground: "white"
                // Разрешены состояния, где прошивка не пишет мотор в steady state
                // (UNWINDING/REWINDING: ток ставится один раз, вмешательства только по событиям)
                enabled: ["DISCONNECTED", "UNINITIALIZED", "MANUAL_BRAKING", "MANUAL_SLOW",
                          "MANUAL_SLOW_SPEED_UP", "MANUAL_SLOW_BACK",
                          "MANUAL_SLOW_BACK_SPEED_UP", "UNWINDING", "REWINDING"].indexOf(Skypuff.state) !== -1
                onPressed:  { fastCurrentMode = false; Skypuff.setManualOverride(true); btnSetTarget(Skypuff.fastErpm()) }
                onReleased: { fastCurrentMode = false; btnSetTarget(0) }
            }

            Item {
                Layout.fillWidth: true
            }

            SkypuffBattery {
                id: batteryBlock
                gauge: sGauge
                Layout.alignment: Qt.AlignHCenter

                Connections {
                    target: Skypuff
                    onIsBatteryBlinkingChanged: { batteryBlock.isBatteryBlinking = Skypuff.isBatteryBlinking; }
                    onIsBatteryWarningChanged: { batteryBlock.isBatteryWarning = Skypuff.isBatteryWarning; }
                    onIsBatteryScaleValidChanged: { batteryBlock.isBatteryScaleValid = Skypuff.isBatteryScaleValid; }

                    onBatteryPercentsChanged: { batteryBlock.batteryPercents = Skypuff.batteryPercents; }
                    onBatteryCellVoltsChanged: { batteryBlock.batteryCellVolts = Skypuff.batteryCellVolts; }

                    onSettingsChanged: {
                        batteryBlock.batteryCells = cfg.battery_cells;
                    }
                }
            }
            Item {
                Layout.fillWidth: true
            }

            // ===== TEST: зелёная кнопка SLOW — постоянные Skypuff.slowErpm() ERPM пока нажата =====
            RoundButton {
                id: rTestSpeed
                Layout.topMargin: -5
                Layout.rightMargin: 5
                text: "SLOW"
                implicitWidth: 100
                implicitHeight: 100
                font.pixelSize: 20
                Material.background: "#388E3C"
                Material.foreground: "white"
                // Разрешены состояния, где прошивка не пишет мотор в steady state
                // (UNWINDING/REWINDING: ток ставится один раз, вмешательства только по событиям)
                enabled: ["DISCONNECTED", "UNINITIALIZED", "MANUAL_BRAKING", "MANUAL_SLOW",
                          "MANUAL_SLOW_SPEED_UP", "MANUAL_SLOW_BACK",
                          "MANUAL_SLOW_BACK_SPEED_UP", "UNWINDING", "REWINDING"].indexOf(Skypuff.state) !== -1
                onPressed:  { Skypuff.setManualOverride(true); btnSetTarget(Skypuff.slowErpm()) }
                onReleased: { btnSetTarget(0) }
            }
        }

        // Повтор команд каждые 100 мс пока кнопка нажата или идёт лестница:
        // 1) плавный разгон/торможение (ERPM-лестница за Ramp time),
        // 2) держит ток/скорость, 3) сбрасывает штатный таймаут VESC
        Timer {
            id: tRedRepeat
            interval: 100
            repeat: true
            running: rTestCurrent.pressed || btnRamping
            onTriggered: {
                // Перегрузка: удержание тока (лестница заморожена)
                if (fastCurrentMode) {
                    VescIf.commands().setCurrent(150)
                    return
                }
                // Шаг лестницы
                if (btnRampTick < btnRampTicksTotal) {
                    btnRampTick++
                    btnErpmNow = Math.round(btnRampStart +
                                            (btnRampTarget - btnRampStart) * btnRampTick / btnRampTicksTotal)
                } else {
                    btnErpmNow = btnRampTarget
                    btnRamping = false
                }
                VescIf.commands().setRpm(btnErpmNow)
                // Торможение завершено после отпускания — полный стоп, ручной режим снят
                if (!rTestCurrent.pressed && !btnRamping) {
                    Skypuff.setManualOverride(false)
                    VescIf.commands().setCurrent(0)
                }
            }
        }

        Timer {
            id: tGreenRepeat
            interval: 100
            repeat: true
            running: rTestSpeed.pressed || btnRamping
            onTriggered: {
                // Шаг лестницы
                if (btnRampTick < btnRampTicksTotal) {
                    btnRampTick++
                    btnErpmNow = Math.round(btnRampStart +
                                            (btnRampTarget - btnRampStart) * btnRampTick / btnRampTicksTotal)
                } else {
                    btnErpmNow = btnRampTarget
                    btnRamping = false
                }
                VescIf.commands().setRpm(btnErpmNow)
                // Торможение завершено после отпускания — полный стоп, ручной режим снят
                if (!rTestSpeed.pressed && !btnRamping) {
                    Skypuff.setManualOverride(false)
                    VescIf.commands().setCurrent(0)
                }
            }
        }

        // Защита зелёной кнопки: ток > 150А → плавный стоп (лестница вниз)
        Connections {
            target: Skypuff
            onMotorKgChanged: {
                if (rTestSpeed.pressed) {
                    var amps = Skypuff.motorKg * cfg.amps_per_kg;
                    if (amps > 150) {
                        rTestSpeed.pressed = false;
                        btnSetTarget(0);
                    }
                }
            }
        }

        // Красная кнопка: скорость fastErpm (плавный разгон), при токе >150А переключаемся на удержание 150А,
        // при спаде тока <140А (гистерезис) возвращаемся в скоростной режим,
        // при разгоне выше fastErpm в режиме тока — снижаем ток (возврат в RPM)
        Connections {
            target: Skypuff
            onMotorKgChanged: {
                if (rTestCurrent.pressed) {
                    var amps = Skypuff.motorKg * cfg.amps_per_kg;
                    if (amps > 150 && !fastCurrentMode) {
                        fastCurrentMode = true;
                        VescIf.commands().setCurrent(150);
                    } else if (amps < 140 && fastCurrentMode) {
                        fastCurrentMode = false;
                        VescIf.commands().setRpm(btnErpmNow);
                    }
                }
            }
            onSpeedMsChanged: {
                if (rTestCurrent.pressed && fastCurrentMode) {
                    if (msToErpm(Skypuff.speedMs) > Skypuff.fastErpm()) {
                        fastCurrentMode = false;
                        VescIf.commands().setRpm(btnErpmNow);  // VESC снизит ток, удерживая заданные ERPM
                    }
                }
            }
        }

        // ===== Fast Rewind: авто-смотка с обходом штатного алгоритма =====
        // Пока BLE на связи и state в {REWINDING, SLOWING, SLOW} — шлём свои команды
        // (скорость + ток), как ручная кнопка FAST. При потере связи команды не
        // уходят, контроллер сам возвращается к штатной медленной смотке.
        // Таймер вооружается только через 10 сек после подключения к контроллеру
        // (frwArmed) — чтобы не вмешиваться в обмен конфигом сразу после коннекта.
        property bool frwArmed: false

        Connections {
            target: VescIf
            onPortConnectedChanged: {
                if (VescIf.isPortConnected()) {
                    frwArmed = false
                    tFrwArm.start()
                } else {
                    frwArmed = false
                    tFrwArm.stop()
                }
            }
        }

        Timer {
            id: tFrwArm
            interval: 10000
            onTriggered: frwArmed = true
        }

        Timer {
            id: tFastRewind
            interval: 100
            repeat: true
            running: frwArmed && Skypuff.fastRewind() && !Skypuff.manualOverride && !frwStopped
            onTriggered: {
                // Активные состояния: FSM покидает REWINDING на -(braking+slowing) ≈ -85 м,
                // поэтому перекрываем и SLOWING/SLOW, пока не дойдём до медленной зоны
                var active = ["REWINDING", "SLOWING", "SLOW"].indexOf(Skypuff.state) !== -1
                if (!active) {
                    if (frwRunning) {
                        frwRunning = false
                        frwCurrentMode = false
                        frwErpmNow = 0
                        VescIf.commands().setCurrent(0)
                    }
                    return
                }

                frwRunning = true

                // drawnMeters: вытянутые метры (положительные), при смотке
                // уменьшаются к нулю (конец троса приближается к лебёдке)
                var pos = Skypuff.drawnMeters
                var zone = Skypuff.rewindSlowZone()
                var amps = Skypuff.motorKg * cfg.amps_per_kg

                // Полностью смотано — стоп, прошивка сама завершит
                if (pos <= 0.05) {
                    frwRunning = false
                    frwCurrentMode = false
                    frwErpmNow = 0
                    VescIf.commands().setCurrent(0)
                    return
                }

                var wantSlow = pos <= zone

                // === Защита от зацепа (двухступенчатая) ===
                if (Math.abs(pos - frwLastPos) < 0.05) {
                    frwStallTicks++
                    if (frwSlowPhase && frwStallTicks > 50) {
                        // Медленная фаза: 5 сек без движения → полный стоп
                        frwStopped = true
                        frwRunning = false
                        frwCurrentMode = false
                        frwErpmNow = 0
                        VescIf.commands().setCurrent(0)
                        Skypuff.postStatus(qsTr("Rope stuck — rewind stopped!"), true)
                        return
                    }
                    if (!frwSlowPhase && frwStallTicks > 20) {
                        // Быстрая фаза: 2 сек без движения → попытка медленной
                        frwSlowPhase = true
                        frwSetTarget(Skypuff.rewindSlowErpm())
                    }
                } else {
                    frwStallTicks = 0
                }
                frwLastPos = pos

                // Переход в медленную фазу (последние метры) — плавное торможение
                if (wantSlow && !frwSlowPhase) {
                    frwSlowPhase = true
                    frwSetTarget(Skypuff.rewindSlowErpm())
                }
                // Выход из медленной зоны (трос снова далеко)
                if (!wantSlow && frwSlowPhase) {
                    frwSlowPhase = false
                    frwSetTarget(Skypuff.rewindErpm())
                }

                // Первый запуск — задаём быструю цель
                if (frwErpmNow === 0 && !frwSlowPhase) {
                    frwSetTarget(Skypuff.rewindErpm())
                }

                // Шаг ERPM-лестницы (линейная интерполяция за Ramp time)
                if (frwRampTick < frwRampTicksTotal) {
                    frwRampTick++
                    frwErpmNow = Math.round(frwRampStart +
                                            (frwRampTarget - frwRampStart) * frwRampTick / frwRampTicksTotal)
                } else {
                    frwErpmNow = frwRampTarget
                }

                var maxCurrent = frwSlowPhase ? Skypuff.rewindSlowMaxCurrent()
                                              : Skypuff.rewindMaxCurrent()
                var hyster = Math.max(5, Math.round(maxCurrent * 0.1))

                // Перегрузка → удержание тока; спад (гистерезис) → назад в RPM
                if (amps > maxCurrent && !frwCurrentMode) {
                    frwCurrentMode = true
                    VescIf.commands().setCurrent(maxCurrent)
                } else if (amps < maxCurrent - hyster && frwCurrentMode) {
                    frwCurrentMode = false
                    VescIf.commands().setRpm(frwErpmNow)
                } else if (!frwCurrentMode) {
                    VescIf.commands().setRpm(frwErpmNow)
                }
            }
        }

        // Новый цикл смотки — снимаем блокировку (после зацепа/Стоп)
        Connections {
            target: Skypuff
            onStateChanged: {
                if (Skypuff.state === "REWINDING") {
                    frwStopped = false
                    frwSlowPhase = false
                    frwStallTicks = 0
                    frwErpmNow = 0
                    frwRampTick = frwRampTicksTotal
                }
            }
        }

        /*GaugeDebug {
            id: debugBlock
            gauge: sGauge
            battery: batteryBlock
            visible: true
        }*/

        // Vertical space
        Item {
            Layout.fillHeight: true
        }

        RealSpinBox {
            id: pullForce

            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 30

            enabled: false
            font.pointSize: page.kgValFontSize
            font.bold: true

            decimals: 1
            from: 1
            suffix: qsTr("Kg")

            onValueModified: Skypuff.sendTerminal("force %1".arg(value))
        }

        RowLayout {
            spacing: 0

            BigRoundButton {
                id: bSetZero
                visible: false
                radius: 0

                text: qsTr("Set zero here")
                font.pixelSize: page.bFontSize

                Layout.fillWidth: true
                Layout.preferredHeight: page.bHeight
                background.anchors.fill: bSetZero
                Material.background: page.bgBlueColor

                onClicked: { confirmResetZero.open() }
            }

            BigRoundButton {
                id: bPrePull
                radius: 0
                enabled: false

                font.pixelSize: page.bFontSize
                Layout.preferredHeight: page.bHeight
                Layout.fillWidth: true
                background.anchors.fill: bPrePull
                Material.background: page.bgBlueColor

                state: "PRE_PULL"
                states: [
                    State {name: "PRE_PULL"; PropertyChanges {target: bPrePull;text: qsTr("Pre Pull")}},
                    State {name: "TAKEOFF_PULL"; PropertyChanges {target: bPrePull;text: qsTr("Takeoff Pull")}},
                    State {name: "PULL"; PropertyChanges {target: bPrePull;text: qsTr("Pull")}},
                    State {name: "FAST_PULL"; PropertyChanges {target: bPrePull;text: qsTr("Fast Pull")}}
                ]

                onClicked: {Skypuff.sendTerminal("set %1".arg(state))}
            }

            BigRoundButton {
                id: bUnwinding
                radius: 0
                enabled: false

                text: qsTr("Unwinding")
                font.pixelSize: page.bFontSize

                Layout.fillWidth: true
                Material.background: page.bgGreenColor
                Layout.preferredHeight: page.bHeight
                background.anchors.fill: bUnwinding

                CustomBorder {
                    visible: parent.enabled
                    commonBorder: false
                    lBorderwidth: 1
                    rBorderwidth: 0
                    tBorderwidth: 0
                    bBorderwidth: 0
                    borderColor: Qt.darker(page.bgGreenColor, 1.2)
                }

                state: "UNWINDING"
                states: [
                    State {name: "UNWINDING"; PropertyChanges {target: bUnwinding; text: qsTr("Unwinding")}},
                    State {name: "BRAKING_EXTENSION"; PropertyChanges {target: bUnwinding; text: qsTr("Brake")}}
                ]

                onClicked: {
                    Skypuff.sendTerminal("set %1".arg(bUnwinding.state))
                }

                Connections {
                    target: Skypuff

                    onBrakingExtensionRangeChanged: {
                        // Brake if possible
                        switch(Skypuff.state) {
                        case "MANUAL_BRAKING":
                            bUnwinding.state = isBrakingExtensionRange ? "BRAKING_EXTENSION" : "UNWINDING"
                            break
                        case "UNWINDING":
                        case "REWINDING":
                            bUnwinding.enabled = isBrakingExtensionRange
                            break
                        }
                    }
                }
            }
        }
    }


    Connections {
        target: Skypuff

        function set_manual_state_visible() {
            // Make MANUAL_BRAKING controls visible
            bSetZero.visible = true

            // Disable normal controls
            bPrePull.visible = false

            // Go back to UNWINDING or BRAKING_EXTENSION?
            bUnwinding.state = Skypuff.isBrakingExtensionRange ? "BRAKING_EXTENSION" : "UNWINDING"
        }

        function set_manual_state_invisible() {
            // Make MANUAL_BRAKING controls visible
            bSetZero.visible = false

            // Disable normal controls
            bPrePull.visible = true
            bPrePull.state = "PRE_PULL"

            // Go back to UNWINDING or BRAKING_EXTENSION?
            bUnwinding.state = Skypuff.isBrakingExtensionRange ? "BRAKING_EXTENSION" : "UNWINDING"
        }

        function onExit(state) {
            switch(state) {
            case "MANUAL_SLOW_SPEED_UP":
            case "MANUAL_SLOW_BACK_SPEED_UP":
            case "MANUAL_SLOW":
            case "MANUAL_SLOW_BACK":
            case "MANUAL_BRAKING":
                bStop.enabled = true

                set_manual_state_invisible()
                break
            case "REWINDING":
            case "UNWINDING":
                bStop.enabled = true
                bUnwinding.enabled = true
                bUnwinding.state = "UNWINDING"
                break
            case "BRAKING":
                bPrePull.enabled = true
                break
            case "DISCONNECTED":
                bStop.enabled = true
                bUnwinding.enabled = true
                bPrePull.enabled = true
                pullForce.enabled = true
                break
            case "SLOW":
            case "SLOWING":
                bStop.enabled = true
                bPrePull.enabled = true
                break
            case "FAST_PULL":
                bPrePull.enabled = true
                bPrePull.state = "PRE_PULL"
                break
            }
        }

        function onEnter(state) {
            switch(state) {
            case "MANUAL_BRAKING":
                set_manual_state_visible()
                bStop.enabled = false
                bUnwinding.enabled = !Skypuff.isPositiveTachometer
                bSetZero.enabled = true
                break
            case "MANUAL_SLOW_SPEED_UP":
            case "MANUAL_SLOW_BACK_SPEED_UP":
            case "MANUAL_SLOW":
            case "MANUAL_SLOW_BACK":
                set_manual_state_visible()
                bUnwinding.enabled = false
                bSetZero.enabled = false
                break
            case "BRAKING":
                bUnwinding.enabled = false
                bUnwinding.state = "UNWINDING"
                bPrePull.enabled = false
                bPrePull.state = "PRE_PULL"
                break
            case "BRAKING_EXTENSION":
                bUnwinding.enabled = true
                bUnwinding.state = "UNWINDING"
                break
            case "REWINDING":
            case "UNWINDING":
                bUnwinding.enabled = Skypuff.isBrakingExtensionRange
                bUnwinding.state = "BRAKING_EXTENSION"
                bPrePull.state = "PRE_PULL"
                break
            case "SLOW":
            case "SLOWING":
                bUnwinding.enabled = false
                bPrePull.enabled = false
                bPrePull.state = "PRE_PULL"
                break
            case "PRE_PULL":
                bPrePull.state = "TAKEOFF_PULL"
                break
            case "TAKEOFF_PULL":
                bPrePull.state = "PULL"
                break
            case "PULL":
                bPrePull.state = "FAST_PULL"
                break
            case "FAST_PULL":
                bPrePull.enabled = false
                break
            case "DISCONNECTED":
                bStop.enabled = false
                bPrePull.enabled = false
                pullForce.enabled = false
                break
            }
        }

        onPositiveTachometerChanged: {
            if (page.state == "MANUAL_BRAKING") {
                bUnwinding.enabled = !isPositiveTachometer
            }
        }

        onStateChanged: {
            if(page.state !== newState) {
                onExit(page.state)
                onEnter(newState)
            }

            page.state = newState
        }

        onSettingsChanged: {
            pullForce.to = cfg.motor_max_kg
            pullForce.stepSize = cfg.motor_max_kg / 30
            pullForce.value = cfg.pull_kg
        }
    }
}
