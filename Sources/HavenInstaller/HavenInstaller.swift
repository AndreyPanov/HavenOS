// HavenInstaller — artifact fetch, cache, and placement layer
//
// This module handles downloading, caching, and extracting service
// artifacts into Haven-managed directories. It bridges the gap between
// planning (which knows *what* to install) and runtime execution
// (which needs artifacts *on disk*).
//
// Key types:
//   ArtifactInstaller         — primary API: install/uninstall artifacts
//   ArtifactDescriptor        — what to install (unitID, source, format)
//   ArtifactSource            — where to fetch from (local file or remote URL)
//   ArtifactFormat            — packaging format (executable, zip, tar.gz)
//   ArtifactInstallResult     — result with install directory and cache status
//   ArtifactCache             — cache management under <base>/Installed/
//   DownloadClient            — protocol for remote downloads (mockable)
//   URLSessionDownloadClient  — production download implementation
//   ArchiveExtractor          — protocol for archive extraction (mockable)
//   ProcessArchiveExtractor   — production extractor using ditto/tar
//   ArtifactInstallerError    — structured errors from installer operations
