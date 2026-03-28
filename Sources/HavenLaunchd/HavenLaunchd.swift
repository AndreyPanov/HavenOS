// HavenLaunchd — launchd job modeling layer
//
// This module translates PreparedRuntime values from the runtime adapter
// layer into deterministic launchd job definitions (property lists).
//
// Key types:
//   LaunchdJob              — models a launchd plist with all required keys
//   LaunchdKeepAlivePolicy  — restart/keep-alive strategies
//   LaunchdLabel            — deterministic label generation (app.haven.<cap>.<unit>)
//
// Current phase:
//   Pure modeling only — no launchctl calls, no file I/O, no process execution.
//   The execution layer (not yet implemented) will use these types to write
//   plists and register jobs with launchd.
