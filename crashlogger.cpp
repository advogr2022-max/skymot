#include "crashlogger.h"

#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <unwind.h>
#include <android/log.h>

// ===== Breadcrumbs ring buffer (async-signal-safe: no malloc, no Qt) =====
#define CRUMBS_N 48
#define CRUMB_LEN 96

static volatile char g_crumbs[CRUMBS_N][CRUMB_LEN];
static volatile int g_crumbIdx = 0;

void crashBreadcrumb(const char *step)
{
    if (!step) {
        return;
    }

    const int idx = g_crumbIdx % CRUMBS_N;
    size_t len = strlen(step);
    if (len >= CRUMB_LEN) {
        len = CRUMB_LEN - 1;
    }
    for (size_t i = 0;i < len;i++) {
        g_crumbs[idx][i] = step[i];
    }
    g_crumbs[idx][len] = '\0';
    g_crumbIdx++;
}

// ===== Crash handler =====
// Writes breadcrumbs + backtrace (PC addresses) to Download/Skymot/crash.log
// using ONLY async-signal-safe calls (open/write/_exit).
// Addresses are raw PCs; resolve with addr2line against the APK .so.

static const char *g_crashPaths[] = {
    "/sdcard/Download/Skymot/crash.log",
    "/storage/emulated/0/Android/data/skymot.winch/files/crash.log",
    "/data/data/skymot.winch/files/crash.log",
    nullptr
};

static int g_crashFd = -1;

static void writeAll(const char *s)
{
    if (!s || g_crashFd < 0) {
        return;
    }
    size_t len = strlen(s);
    size_t off = 0;
    while (off < len) {
        ssize_t w = write(g_crashFd, s + off, len - off);
        if (w <= 0) {
            break;
        }
        off += (size_t)w;
    }
}

// Write a pointer as hex (async-signal-safe, no snprintf)
static void writeHexPtr(const void *p)
{
    if (g_crashFd < 0) {
        return;
    }
    char buf[24];
    buf[0] = '0';
    buf[1] = 'x';
    uintptr_t v = (uintptr_t)p;
    int i = 2;
    bool started = false;
    for (int shift = (int)(sizeof(uintptr_t) * 8) - 4; shift >= 0; shift -= 4) {
        int nib = (int)((v >> shift) & 0xF);
        if (nib || started || shift == 0) {
            started = true;
            buf[i++] = nib < 10 ? ('0' + nib) : ('a' + nib - 10);
        }
    }
    buf[i++] = '\n';
    write(g_crashFd, buf, (size_t)i);
}

// _Unwind_Backtrace callback: collect PCs into static array (signal-safe)
static _Unwind_Reason_Code unwindCb(struct _Unwind_Context *ctx, void *arg)
{
    uintptr_t *pcs = (uintptr_t *)arg;
    const int max = (int)(pcs[0]);      // pcs[0] = count
    const int idx = (int)pcs[1];        // pcs[1] = index
    if (idx >= max) {
        return _URC_END_OF_STACK;
    }
    pcs[2 + idx] = _Unwind_GetIP(ctx);
    pcs[1] = (uintptr_t)(idx + 1);
    return _URC_NO_REASON;
}

static void crashHandler(int sig, siginfo_t *si, void *ctx)
{
    (void)ctx;

    g_crashFd = -1;
    for (int i = 0; g_crashPaths[i] && g_crashFd < 0; i++) {
        g_crashFd = open(g_crashPaths[i], O_WRONLY | O_CREAT | O_APPEND, 0666);
    }

    if (g_crashFd >= 0) {
        const char *sigName = "SIGNAL";
        switch (sig) {
        case SIGSEGV: sigName = "SIGSEGV"; break;
        case SIGABRT: sigName = "SIGABRT"; break;
        case SIGBUS:  sigName = "SIGBUS";  break;
        case SIGFPE:  sigName = "SIGFPE";  break;
        case SIGILL:  sigName = "SIGILL";  break;
        default: break;
        }

        writeAll("\n===== CRASH ");
        writeAll(sigName);
        writeAll(" sig=");
        // sig as decimal
        {
            char sbuf[16];
            int si2 = sig, p = 0;
            if (si2 == 0) sbuf[p++] = '0';
            while (si2 > 0) { sbuf[p++] = (char)('0' + si2 % 10); si2 /= 10; }
            // reverse
            for (int a = 0, b = p - 1; a < b; a++, b--) {
                char t = sbuf[a]; sbuf[a] = sbuf[b]; sbuf[b] = t;
            }
            sbuf[p] = '\0';
            writeAll(sbuf);
        }
        writeAll(" addr=");
        writeHexPtr((si && si->si_addr) ? si->si_addr : (void *)0);

        writeAll("--- last steps ---\n");
        const int total = g_crumbIdx < CRUMBS_N ? g_crumbIdx : CRUMBS_N;
        for (int i = 0; i < total; i++) {
            const int idx = (g_crumbIdx - total + i) % CRUMBS_N;
            if (g_crumbs[idx][0]) {
                writeAll("  ");
                writeAll((const char *)g_crumbs[idx]);
                writeAll("\n");
            }
        }

        writeAll("--- backtrace PCs ---\n");
        uintptr_t pcs[2 + 48];
        pcs[0] = 48;
        pcs[1] = 0;
        _Unwind_Backtrace(unwindCb, pcs);
        const int n = (int)pcs[1];
        for (int i = 0; i < n; i++) {
            writeHexPtr((void *)pcs[2 + i]);
        }

        // Dump /proc/self/maps so the .so load base can be computed and the
        // PCs above resolved to symbols (open/read/write are async-signal-safe).
        writeAll("--- /proc/self/maps ---\n");
        {
            int mfd = open("/proc/self/maps", O_RDONLY);
            if (mfd >= 0) {
                char mbuf[4096];
                ssize_t mr;
                while ((mr = read(mfd, mbuf, sizeof(mbuf))) > 0) {
                    write(g_crashFd, mbuf, (size_t)mr);
                }
                close(mfd);
            }
        }
        writeAll("=================\n");
        close(g_crashFd);
        g_crashFd = -1;
    }

    __android_log_print(ANDROID_LOG_FATAL, "SkymotCrash",
                        "signal %d (%s) at %p",
                        sig, sig == SIGSEGV ? "SIGSEGV" : "SIG",
                        (si && si->si_addr) ? si->si_addr : (void *)0);

    // Do not return / re-raise: would recurse. Exit with signal status.
    _exit(128 + sig);
}

void installCrashHandler()
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_sigaction = crashHandler;
    sa.sa_flags = SA_SIGINFO;
    sigemptyset(&sa.sa_mask);

    sigaction(SIGSEGV, &sa, nullptr);
    sigaction(SIGABRT, &sa, nullptr);
    sigaction(SIGBUS, &sa, nullptr);
    sigaction(SIGFPE, &sa, nullptr);
    sigaction(SIGILL, &sa, nullptr);
}
