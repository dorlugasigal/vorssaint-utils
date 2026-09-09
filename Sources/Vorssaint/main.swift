// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

#if VORSSAINT_DEVELOPMENT
if let path = ProcessInfo.processInfo.environment["VORSSAINT_DIAGNOSTIC_LOG"] {
    guard freopen(path, "a", stderr) != nil else {
        fputs("Could not open the requested development diagnostic log.\n", stderr)
        exit(1)
    }
    setbuf(stderr, nil)
    NSSetUncaughtExceptionHandler { exception in
        fputs("\(exception.name.rawValue): \(exception.reason ?? "")\n\(exception.callStackSymbols.joined(separator: "\n"))\n", stderr)
    }
}
#endif

SuperKeyMappingGuard.runIfRequestedAndExit()
Defaults.register()
MouseAccelerationGuard.runIfRequestedAndExit()
MouseAccelerationService.recoverPendingAtLaunch()

if CommandLine.arguments.contains("--selftest") {
    SelfTest.runAndExit()
}
if CommandLine.arguments.contains("--selftest-annotation-ui") {
    SelfTest.runAnnotationUIAndExit()
}
if CommandLine.arguments.contains("--sensors") {
    SensorDump.runAndExit()
}
if CommandLine.arguments.contains("--uninstall") {
    Uninstaller.runAndExit()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
