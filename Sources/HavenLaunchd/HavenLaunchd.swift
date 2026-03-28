// HavenLaunchd — launchd job modeling and execution layer
//
// This module translates PreparedRuntime values from the runtime adapter
// layer into deterministic launchd job definitions (property lists) and
// manages their lifecycle through launchctl.
//
// Modeling types:
//   LaunchdJob              — models a launchd plist with all required keys
//   LaunchdKeepAlivePolicy  — restart/keep-alive strategies
//   LaunchdLabel            — deterministic label generation (app.haven.<cap>.<unit>)
//
// Execution types:
//   LaunchdController       — install/uninstall/start/stop/status operations
//   LaunchdPaths            — deterministic LaunchAgents path resolution
//   LaunchdJobStatus        — observed runtime status of a job
//   LaunchctlClient         — protocol abstracting launchctl command execution
//   ProcessLaunchctlClient  — production implementation using Foundation.Process
//   LaunchdControllerError  — structured errors from controller operations
