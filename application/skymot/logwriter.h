#pragma once

#include <QString>

// File logging to Download/Skymot/<yyyyMMdd_HHmm>.log (general)
// and Download/Skymot/<yyyyMMdd_HHmm>smot.log (rewind session).
// Implemented in main.cpp; thread-safe.

void logGeneral(const QString &line);
void logSmot(const QString &line);
