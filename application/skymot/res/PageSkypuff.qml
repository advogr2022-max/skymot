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
    property bool fastCurrentMode: false  // красная кнопка: true = держим ток 150А (перегрузка)

    // ВАЖНО: page.cfg — это appConfig VESC, в нём НЕТ полей лебёдки (amps_per_kg, wheel_diameter_mm,
    // gear_ratio, motor_poles, длины зон). Они приходят из прошивки сигналом
    // Skypuff.settingsChanged(cfg) и кэшируются здесь. Раньше код читал их прямо из page.cfg,
    // получал undefined и NaN — из-за чего защита по току 150А и msToErpm() не работали ВООБЩЕ.
    property real skAmpsPerKg: 3.333
    property real skWheelDiameterMm: 270
    property real skGearRatio: 1
    property int  skMotorPoles: 32
    property real skBrakingMeters: 30
    property real skSlowingMeters: 55

    // Граница жёсткого запрета для красной кнопки FAST: конец зоны замедления (по умолчанию 30 + 55 = 85 м)
    property real fastMinMeters: page.skBrakingMeters + page.skSlowingMeters

    // ===== Авто-смотка (автоматический аналог красной кнопки) =====
    // Включается: состояние REWINDING держится непрерывно дольше 2 с И трос дальше fastMinMeters (85 м).
    // Команды те же, что у кнопки FAST: setRpm(fastErpm) каждые 100 мс + удержание 150 А при перегрузе.
    // Выключается: пересечение границы 85 м, выход из REWINDING, кнопка Stop.
    // Ручные кнопки имеют приоритет: пока нажата любая из них, авто-режим команды не шлёт.
    property bool autoFastActive: false        // авто-режим шлёт команды прямо сейчас
    property bool autoFastCurrentMode: false   // авто-режим держит ток 150 А (перегрузка)
    property bool autoFastBlocked: false       // запрет до следующего входа в REWINDING (нажали Stop)

    function autoFastStop() {
        if (page.autoFastActive) {
            page.autoFastActive = false
            page.autoFastCurrentMode = false
            VescIf.commands().setCurrent(0)
        }
    }

    // скорость троса (м/с) → ERPM мотора
    function msToErpm(ms) {
        var mpr = (page.skWheelDiameterMm / 1000) / page.skGearRatio * Math.PI; // м на оборот вала
        return (ms / mpr * 60) * (page.skMotorPoles / 2);
    }

    // ток мотора (А): Skypuff.motorKg в C++ уже поделён на amps_per_kg, возвращаем обратно амперы
    function motorAmps() {
        return Skypuff.motorKg * page.skAmpsPerKg;
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
                    page.autoFastBlocked = true   // Stop гасит авто-смотку до следующего входа в REWINDING
                    page.autoFastStop()
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

            // Красная надпись состояния, пока приложение шлёт мотору свои команды:
            // авто-смотка (без нажатия) или нажатая кнопка FAST/SLOW. Обычный режим — чёрная.
            appOverride: page.autoFastActive || rTestCurrent.pressed || rTestSpeed.pressed

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
                // Оранжевая, пока работает авто-смотка (мотор тянет без нажатия) — видно, что режим активен
                Material.background: page.autoFastActive ? "#FF6D00" : "#D32F2F"
                Material.foreground: "white"
                // Разрешены состояния, где прошивка не пишет мотор в steady state
                // (UNWINDING/REWINDING: ток ставится один раз, вмешательства только по событиям)
                // + ЖЁСТКОЕ ОГРАНИЧЕНИЕ ПО ПОЗИЦИИ: FAST запрещена ближе конца зоны замедления
                // (braking_length + slowing_length, по умолчанию 30 + 55 = 85 м) — там смоткой
                // управляет прошивка (SLOWING/SLOW/BRAKING) и пилот у земли.
                // В DISCONNECTED позиции нет и мотор не подключён — кнопка остаётся для стендовой проверки.
                enabled: (["DISCONNECTED", "UNINITIALIZED", "MANUAL_BRAKING", "MANUAL_SLOW",
                           "MANUAL_SLOW_SPEED_UP", "MANUAL_SLOW_BACK",
                           "MANUAL_SLOW_BACK_SPEED_UP", "UNWINDING", "REWINDING"].indexOf(Skypuff.state) !== -1)
                         && (Skypuff.state === "DISCONNECTED" || Skypuff.drawnMeters > page.fastMinMeters)
                onPressed:  { fastCurrentMode = false; VescIf.commands().setRpm(Skypuff.fastErpm()) }
                onReleased: { fastCurrentMode = false; VescIf.commands().setCurrent(0) }
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
                // Зелёная кнопка разрешена ДОПОЛНИТЕЛЬНО в тормозных/замедляющих состояниях
                // (SLOWING, SLOW, BRAKING, BRAKING_EXTENSION) — нужно тянуть по нажатию и в них.
                // Безопасно: прошивка в этих состояниях задаёт мотор ОДИН РАЗ на входе
                // (smooth_motor_brake/smooth_motor_speed -> next_smooth_motor_adjustment = INT_MAX),
                // а BRAKING перекладывает тормоз только по таймауту VESC (наши команды его сбрасывают).
                enabled: ["DISCONNECTED", "UNINITIALIZED", "MANUAL_BRAKING", "MANUAL_SLOW",
                          "MANUAL_SLOW_SPEED_UP", "MANUAL_SLOW_BACK",
                          "MANUAL_SLOW_BACK_SPEED_UP", "UNWINDING", "REWINDING",
                          "SLOWING", "SLOW", "BRAKING", "BRAKING_EXTENSION"].indexOf(Skypuff.state) !== -1
                onPressed:  VescIf.commands().setRpm(Skypuff.slowErpm())
                onReleased: VescIf.commands().setCurrent(0)
            }
        }

        // Повтор команд каждые 100 мс пока кнопка нажата:
        // 1) держит ток/скорость, 2) сбрасывает штатный таймаут VESC
        // (при потере BLE мотор сам остановится через App Settings → Timeout)
        Timer {
            id: tRedRepeat
            interval: 100
            repeat: true
            running: rTestCurrent.pressed
            onTriggered: {
                // ЖЁСТКИЙ СТОП по позиции: подошли к границе зоны замедления (85 м по умолчанию) —
                // мгновенно снимаем тягу и отпускаем кнопку, даже если палец на ней
                if (Skypuff.state !== "DISCONNECTED" && Skypuff.drawnMeters <= page.fastMinMeters) {
                    rTestCurrent.pressed = false
                    fastCurrentMode = false
                    VescIf.commands().setCurrent(0)
                    return
                }
                if (fastCurrentMode) {
                    VescIf.commands().setCurrent(150)
                } else {
                    VescIf.commands().setRpm(Skypuff.fastErpm())
                }
            }
        }

        Timer {
            id: tGreenRepeat
            interval: 100
            repeat: true
            running: rTestSpeed.pressed
            onTriggered: VescIf.commands().setRpm(Skypuff.slowErpm())
        }

        // Взвод авто-смотки: REWINDING непрерывно дольше 2 с и трос дальше границы 85 м.
        // Любое нарушение условия обнуляет отсчёт (Timer перезапускается при running false->true).
        Timer {
            id: tAutoFastArm
            interval: 2000
            repeat: false
            running: Skypuff.state === "REWINDING"
                     && Skypuff.drawnMeters > page.fastMinMeters
                     && !page.autoFastBlocked && !page.autoFastActive
                     && !rTestCurrent.pressed && !rTestSpeed.pressed
            onTriggered: {
                page.autoFastCurrentMode = false
                page.autoFastActive = true
            }
        }

        // Авто-смотка: те же команды и защиты, что у красной кнопки, но без нажатия
        Timer {
            id: tAutoFast
            interval: 100
            repeat: true
            running: page.autoFastActive && !rTestCurrent.pressed && !rTestSpeed.pressed
            onTriggered: {
                // Жёсткие условия выхода: вышли из REWINDING или пересекли границу 85 м
                if (Skypuff.state !== "REWINDING" || Skypuff.drawnMeters <= page.fastMinMeters) {
                    page.autoFastStop()
                    return
                }

                var amps = motorAmps()
                if (amps > 150 && !page.autoFastCurrentMode)
                    page.autoFastCurrentMode = true
                else if (amps < 140 && page.autoFastCurrentMode)
                    page.autoFastCurrentMode = false

                if (page.autoFastCurrentMode)
                    VescIf.commands().setCurrent(150)
                else
                    VescIf.commands().setRpm(Skypuff.fastErpm())
            }
        }

        // Защита зелёной кнопки: ток > 150А → стоп
        Connections {
            target: Skypuff
            onMotorKgChanged: {
                if (rTestSpeed.pressed) {
                    var amps = motorAmps();
                    if (amps > 150) {
                        rTestSpeed.pressed = false;
                        VescIf.commands().setCurrent(0);
                    }
                }
            }
        }

        // Красная кнопка: скорость Skypuff.fastErpm() ERPM, при токе >150А переключаемся на удержание 150А,
        // при спаде тока <140А (гистерезис) возвращаемся в скоростной режим,
        // при разгоне выше Skypuff.fastErpm() ERPM в режиме тока — снижаем ток (возврат в RPM)
        Connections {
            target: Skypuff
            onMotorKgChanged: {
                if (rTestCurrent.pressed) {
                    var amps = motorAmps();
                    if (amps > 150 && !fastCurrentMode) {
                        fastCurrentMode = true;
                        VescIf.commands().setCurrent(150);
                    } else if (amps < 140 && fastCurrentMode) {
                        fastCurrentMode = false;
                        VescIf.commands().setRpm(Skypuff.fastErpm());
                    }
                }
            }
            onSpeedMsChanged: {
                if (rTestCurrent.pressed && fastCurrentMode) {
                    if (msToErpm(Skypuff.speedMs) > Skypuff.fastErpm()) {
                        fastCurrentMode = false;
                        VescIf.commands().setRpm(Skypuff.fastErpm());  // VESC снизит ток, удерживая заданные ERPM
                    }
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
            // Авто-смотка живёт только внутри REWINDING; выход из него гасит её и снимает запрет от Stop
            if (newState !== "REWINDING") {
                page.autoFastStop()
                page.autoFastBlocked = false
            }

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

            // Кэш параметров лебёдки для защиты по току, msToErpm() и границы запрета FAST
            page.skAmpsPerKg = cfg.amps_per_kg
            page.skWheelDiameterMm = cfg.wheel_diameter_mm
            page.skGearRatio = cfg.gear_ratio
            page.skMotorPoles = cfg.motor_poles
            page.skBrakingMeters = cfg.braking_length_meters
            page.skSlowingMeters = cfg.slowing_length_meters
        }
    }
}
