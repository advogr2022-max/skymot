#ifndef CRASHLOGGER_H
#define CRASHLOGGER_H

// Breadcrumbs: последние N шагов до краша (async-signal-safe ring buffer).
// Вызывается из ключевых точек кода. В crash-handler'е буфер дописывается
// в crash.log вместе с backtrace.
void crashBreadcrumb(const char *step);

// Установить обработчики SIGSEGV/SIGABRT/SIGBUS/SIGFPE/SIGILL.
// Пишет crash.log (breadcrumbs + backtrace) в Download/Skymot.
void installCrashHandler();

#endif // CRASHLOGGER_H
