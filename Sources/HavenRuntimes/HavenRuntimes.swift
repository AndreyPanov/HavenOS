// HavenRuntimes — runtime adapter layer
//
// This module provides the RuntimeAdapter protocol and built-in adapters
// that prepare RuntimeUnits for launch in their respective execution
// environments (native binary, Python).
//
// Key types:
//   RuntimeAdapter          — protocol for runtime-specific preparation
//   PreparedRuntime         — launch-ready output from an adapter
//   NativeRuntimeAdapter    — adapter for native macOS binaries
//   PythonRuntimeAdapter    — adapter for Haven-managed Python apps
//   RuntimeAdapterRegistry  — resolves adapter by RuntimeType
//   RuntimeAdapterError     — errors during preparation/teardown
