/*
    Copyright 2018 Benjamin Vedder	benjamin@vedder.se

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <QMutex>
#include <QStandardPaths>
#include <QElapsedTimer>
#include <QTimer>
#include <QDir>
#include <QFileInfo>
#include <android/log.h>
#include <QtAndroidExtras/QtAndroid>
#include <QtAndroidExtras/QAndroidJniObject>
#include "vescinterface.h"
#include "skypuff.h"
#include "utility.h"
#include "crashlogger.h"

// ===== File logs: Download/Skymot/<yyyyMMdd_HHmm>.log (general) and
// Download/Skymot/<yyyyMMdd_HHmm>smot.log (rewind session) =====
// Scoped Storage (targetSdk 34) forbids direct writes to /sdcard/Download,
// so we try Download first, then Android/data, then internal files dir.
#include "logwriter.h"

static QMutex g_logMutex;
static QStringList g_pendingLog;   // buffer until channels are ready
static QElapsedTimer g_startTimer;
static bool g_startTimerInit = false;
static bool g_initAttempted = false;

static QFile g_fileGeneral;   // Download/Skymot (or fallback)
static QFile g_fileSmot;

// Try to open a log file. Preferred: Download/Skymot (user-visible).
// Fallback 1: Android/data/skymot.winch/files (visible via USB/MTP).
// Fallback 2: internal files dir (always works).
static QFile *openLogFile(QFile &f, const QString &name)
{
    const QStringList candidates = {
        QStringLiteral("/sdcard/Download/Skymot/") + name,
        QStringLiteral("/storage/emulated/0/Android/data/skymot.winch/files/") + name,
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/") + name
    };
    for (const QString &path : candidates) {
        QDir().mkpath(QFileInfo(path).absolutePath());
        f.setFileName(path);
        if (f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
            // 666: file managers (different UID) must see/read the logs
            f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner |
                             QFileDevice::ReadGroup | QFileDevice::WriteGroup |
                             QFileDevice::ReadOther | QFileDevice::WriteOther);
            __android_log_print(ANDROID_LOG_INFO, "SkymotLog", "log '%s' -> %s",
                                qPrintable(name), qPrintable(path));
            return &f;
        }
    }
    return nullptr;
}

// Register a written log file in MediaStore so that file managers
// (Files app, etc.) can see it on Android 11+ (Scoped Storage).
// Pure file-system writes are invisible to file managers otherwise.
static void scanFileInMediaStore(const QString &path)
{
    QAndroidJniEnvironment env;
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
    }

    QAndroidJniObject context = QtAndroid::androidContext();
    if (!context.isValid()) {
        return;
    }

    jclass stringClass = env->FindClass("java/lang/String");
    if (!stringClass) {
        env->ExceptionClear();
        return;
    }
    jobjectArray paths = env->NewObjectArray(1, stringClass, nullptr);
    if (!paths) {
        env->ExceptionClear();
        return;
    }
    jstring jpath = env->NewStringUTF(path.toUtf8().constData());
    if (jpath) {
        env->SetObjectArrayElement(paths, 0, jpath);
        env->DeleteLocalRef(jpath);
    }

    // MediaScannerConnection.scanFile(Context, String[], String[], OnScanCompletedListener)
    jclass mscClass = env->FindClass("android/media/MediaScannerConnection");
    if (mscClass) {
        jmethodID scanMethod = env->GetStaticMethodID(mscClass, "scanFile",
            "(Landroid/content/Context;[Ljava/lang/String;[Ljava/lang/String;Landroid/media/MediaScannerConnection$OnScanCompletedListener;)V");
        if (scanMethod) {
            env->CallStaticVoidMethod(mscClass, scanMethod,
                                      context.object(), paths, nullptr, nullptr);
            __android_log_print(ANDROID_LOG_INFO, "SkymotLog", "MediaStore scan: %s",
                                qPrintable(path));
        }
    }
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
    }
    env->DeleteLocalRef(paths);
}

static void initLogFile()
{
    crashBreadcrumb("initLogFile");
    __android_log_print(ANDROID_LOG_INFO, "SkymotLog", "initLogFile called");
    QString base = QDateTime::currentDateTime().toString("yyyyMMdd_HHmm");
    openLogFile(g_fileGeneral, base + ".log");
    openLogFile(g_fileSmot, base + "smot.log");

    // Make the log files visible to file managers (MediaStore on Android 11+)
    // ⚠️ DISABLED (diagnostic build v1.4.1-crashdbg-noscan): raw JNI
    // scanFileInMediaStore() is the prime suspect for CheckJNI abort on BLE
    // connect (QAndroidJniObject::fromString -> libart abort right inside
    // BleUart::startConnect). Files still get written, just not registered
    // in MediaStore. Re-enable after the crash is confirmed fixed.
#if 0
    if (g_fileGeneral.isOpen()) {
        scanFileInMediaStore(g_fileGeneral.fileName());
    }
    if (g_fileSmot.isOpen()) {
        scanFileInMediaStore(g_fileSmot.fileName());
    }
#endif

    QMutexLocker locker(&g_logMutex);
    QStringList pending = g_pendingLog;
    g_pendingLog.clear();
    for (const QString &line : pending) {
        QByteArray data = (line + "\n").toUtf8();
        if (g_fileGeneral.isOpen()) {
            g_fileGeneral.write(data);
            g_fileGeneral.flush();
        }
    }
}

void logGeneral(const QString &line)
{
    QMutexLocker locker(&g_logMutex);
    QByteArray data = (line + "\n").toUtf8();
    if (g_fileGeneral.isOpen()) {
        g_fileGeneral.write(data);
        g_fileGeneral.flush();
    } else {
        g_pendingLog.append(line);
    }
}

void logSmot(const QString &line)
{
    QMutexLocker locker(&g_logMutex);
    QByteArray data = (line + "\n").toUtf8();
    if (g_fileSmot.isOpen()) {
        g_fileSmot.write(data);
        g_fileSmot.flush();
    }
    // smot lines also go to the general log (single source of truth)
    if (g_fileGeneral.isOpen()) {
        g_fileGeneral.write(data);
        g_fileGeneral.flush();
    } else {
        g_pendingLog.append(line);
    }
}

void logMessageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    (void)ctx;

    if (!g_startTimerInit) {
        g_startTimer.start();
        g_startTimerInit = true;
    }

    QString line = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss.zzz") + " ";
    switch (type) {
    case QtDebugMsg:    line += "D"; break;
    case QtInfoMsg:     line += "I"; break;
    case QtWarningMsg:  line += "W"; break;
    case QtCriticalMsg: line += "C"; break;
    case QtFatalMsg:    line += "F"; break;
    }
    line += " " + msg;

    // Delayed init (JNI-safe after grace period). Called WITHOUT holding the
    // mutex: JNI may emit qWarning which re-enters this handler.
    bool needInit = false;
    {
        QMutexLocker locker(&g_logMutex);
        if (!g_fileGeneral.isOpen() && !g_initAttempted
                && g_startTimer.elapsed() > 3000) {
            g_initAttempted = true;
            needInit = true;
        }
    }
    if (needInit) {
        initLogFile();
    }
    logGeneral(line);
}

static VescInterface * vesc = NULL;
static Skypuff * skypuff = NULL;

QObject *vescinterface_singletontype_provider(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    (void)engine;
    (void)scriptEngine;

    if(!vesc)
        vesc = new VescInterface();

    Utility::keepScreenOn(true);

    vesc->fwConfig()->loadParamsXml("://res/config/fw.xml");
    Utility::configLoadLatest(vesc);


    return vesc;
}

QObject *skypuff_singletontype_provider(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    (void)engine;
    (void)scriptEngine;

    if(!vesc)
        vesc = new VescInterface();

    if(!skypuff)
        skypuff = new Skypuff(vesc);

    return skypuff;
}

QObject *utility_singletontype_provider(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    (void)engine;
    (void)scriptEngine;

    Utility *util = new Utility();

    return util;
}

int main(int argc, char *argv[])
{
    // Settings
    QCoreApplication::setOrganizationName("VESC");
    QCoreApplication::setOrganizationDomain("vesc-project.com");
    QCoreApplication::setApplicationName("VESC Application");

    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    QGuiApplication app(argc, argv);

    // File logs to Download/Skymot (see logwriter.h). Init after startup grace
    // period: JNI (MediaStore) is only safe once QtActivity is fully up.
    // Both triggers used: QTimer (primary) and first log message after 3 s (backup).
    qInstallMessageHandler(logMessageHandler);
    qDebug() << "=== Skymot starting ===";
    QTimer::singleShot(3000, &app, initLogFile);

    // Crash handler: SIGSEGV/SIGABRT etc. -> breadcrumbs + backtrace to
    // Download/Skymot/crash.log (diagnostic build only).
    installCrashHandler();
    crashBreadcrumb("main: handler installed");

    QQmlApplicationEngine engine;

    qmlRegisterSingletonType<VescInterface>("Vedder.vesc.vescinterface", 1, 0, "VescIf", vescinterface_singletontype_provider);
    qmlRegisterSingletonType<Skypuff>("SkyPuff.vesc.winch", 1, 0, "Skypuff", skypuff_singletontype_provider);
    qmlRegisterSingletonType<Utility>("Vedder.vesc.utility", 1, 0, "Utility", utility_singletontype_provider);
#ifdef HAS_BLUETOOTH
    qmlRegisterType<BleUart>("Vedder.vesc.bleuart", 1, 0, "BleUart");
#endif
    qmlRegisterType<Commands>("Vedder.vesc.commands", 1, 0, "Commands");
    qmlRegisterType<ConfigParams>("Vedder.vesc.configparams", 1, 0, "ConfigParams");
    qRegisterMetaType<QMLable_skypuff_config>();
    
    engine.load(QUrl(QLatin1String("qrc:/res/main.qml")));
    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
