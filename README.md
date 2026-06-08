# Trace Windows Builder

A PowerShell-based build system for compiling and packaging [Trace](https://buildwithtrace.com) on Windows. Trace is an AI-powered PCB design tool forked from [KiCad](https://www.kicad.org/).

## Overview

This repository contains all the tooling needed to:
- Build Trace from source on Windows
- Package Trace into NSIS installers
- Manage build dependencies via vcpkg
- Support multiple architectures (x64, x86, arm64)

The builder uses PowerShell scripting with modular functions that can be individually debugged and executed.

## Prerequisites

Before using this builder, ensure you have the following installed:

### Required Software

| Software | Version | Notes |
|----------|---------|-------|
| **Windows** | 10/11 or Server 2019+ | PowerShell 5.1+ required (included) |
| **Visual Studio** | 2019 or 2022 | Community, Professional, or Enterprise |
| **Git for Windows** | Latest | https://git-scm.com/download/win |

### Visual Studio Workloads

When installing Visual Studio, ensure these workloads are selected:
- **Desktop development with C++**
- **C++ CMake tools for Windows** (included in above workload)

### Disk Space

- **Minimum:** ~30 GB free space
- **Recommended:** ~50 GB free space (for full build with 3D models)

## Folder Structure

The builder expects the following folder layout:

```
YourWorkspace/
├── trace-win-builder/    # This repository
└── Trace/                # Trace source code (cloned separately)
```

> **Note:** The Trace source folder must be named `Trace` and located alongside the builder.

## Quick Start

### 1. Clone the Repositories

```powershell
# Create workspace folder
mkdir C:\Dev\TraceWorkspace
cd C:\Dev\TraceWorkspace

# Clone the builder
git clone https://github.com/YourOrg/trace-win-builder.git

# Clone Trace source (adjust URL as needed)
git clone https://gitlab.com/trace/code/trace.git Trace
```

### 2. Initialize the Build Environment

```powershell
cd trace-win-builder

# Download and set up build tools (CMake, Ninja, NSIS, etc.)
.\build.ps1 -Init
```

### 3. Build vcpkg Dependencies

```powershell
# Build all required libraries (this takes a while on first run)
.\build.ps1 -Vcpkg -Latest -Arch x64
```

### 4. Build Trace

```powershell
# Build Trace (Release mode)
.\build.ps1 -Build -Latest -Arch x64 -BuildType Release
```

### 5. Create Installer

```powershell
# Prepare and package into NSIS installer
.\build.ps1 -Package -Arch x64 -BuildConfigName trace-nightly
```

The installer will be created in the `.out/` folder.

## Build Commands Reference

### Main Build Script (`build.ps1`)

| Command | Description |
|---------|-------------|
| `.\build.ps1 -Init` | Download and set up build tools |
| `.\build.ps1 -Env -Arch x64` | Set up MSVC environment variables |
| `.\build.ps1 -Vcpkg -Latest -Arch x64` | Build/update vcpkg dependencies |
| `.\build.ps1 -Build -Latest -Arch x64` | Build Trace from source |
| `.\build.ps1 -PreparePackage -Arch x64` | Prepare files for packaging |
| `.\build.ps1 -Package -Arch x64` | Create NSIS installer |

### Common Options

| Option | Values | Description |
|--------|--------|-------------|
| `-Arch` | `x64`, `x86`, `arm64` | Target architecture |
| `-BuildType` | `Release`, `Debug` | Build configuration |
| `-BuildConfigName` | `trace-nightly`, etc. | Build config from `build-configs/` |
| `-Latest` | (switch) | Pull latest source before building |
| `-Lite` | (switch) | Create lite installer (no libraries) |

### Examples

```powershell
# Full release build for x64
.\build.ps1 -Build -Latest -Arch x64 -BuildType Release

# Debug build
.\build.ps1 -Build -Arch x64 -BuildType Debug

# Create lite installer (downloads libraries during install)
.\build.ps1 -Package -Arch x64 -Lite

# Build for 32-bit Windows
.\build.ps1 -Vcpkg -Latest -Arch x86
.\build.ps1 -Build -Latest -Arch x86
```

## Helper Scripts

### `create_trace_nsis_installer.ps1`

A simplified script for common installer creation tasks:

```powershell
# Clean rebuild and create full installer
.\create_trace_nsis_installer.ps1 -Rebuild -Full

# Clean rebuild and create lite installer
.\create_trace_nsis_installer.ps1 -Rebuild -Lite

# Create installer without rebuilding (uses existing build)
.\create_trace_nsis_installer.ps1 -Full
```

### `symbols.ps1`

Manages symbol storage for debugging:

```powershell
# Publish symbols to a symbol store
.\symbols.ps1 -Publish -SourceZipPath .\artifacts\ -SymbolStore D:\SymbolStore
```

## Configuration

### `settings.json`

User-specific settings are stored in `settings.json`. Copy from the example to get started:

```powershell
Copy-Item settings.json.example settings.json
```

Available settings:

| Setting | Description | Default |
|---------|-------------|---------|
| `VcpkgPath` | Path to vcpkg (empty = auto-clone) | `""` |
| `VcpkgPlatformToolset` | MSVC toolset version | `"v143"` |
| `VsVersionMin` | Minimum VS version | `"16.0"` |
| `VsVersionMax` | Maximum VS version | `"17.99"` |
| `UseMsvcCmake` | Use VS-bundled CMake | `true` |
| `SignSubjectName` | Code signing certificate name | `""` |
| `SentryDsn` | Sentry error reporting DSN | `""` |

> `settings.json` is gitignored — keep machine-specific paths and secrets out of git.

### Environment overrides (`.env`)

For machine-specific or secret config you'd rather not put in `settings.json`, set
environment variables (or copy `.env.example` to `.env`, which the installer script loads
automatically). These take precedence over `settings.json`:

| Env var | Overrides |
|---------|-----------|
| `TRACE_VCPKG_PATH` / `VCPKG_ROOT` | `VcpkgPath` (then falls back to the bundled `./vcpkg` submodule) |
| `TRACE_SENTRY_DSN` | `SentryDsn` |
| `TRACE_SIGN_SUBJECT_NAME` | `SignSubjectName` |
| `TRACE_VS_VERSION_MIN` / `TRACE_VS_VERSION_MAX` | VS version range |
| `TRACE_VCPKG_PLATFORM_TOOLSET` | `VcpkgPlatformToolset` |
| `AMPLITUDE_API_KEY` | Amplitude analytics key (read directly during build) |

If `VcpkgPath` is unset everywhere, the build uses the bundled `./vcpkg` submodule
(`git submodule update --init vcpkg`).

### Build Configurations

Build configurations are stored in `build-configs/` as JSON files. The default is `trace-nightly.json`.

To use a specific configuration:

```powershell
.\build.ps1 -Build -Arch x64 -BuildConfigName trace-nightly
```

## Build Artifacts

After a successful build, you'll find:

| Location | Contents |
|----------|----------|
| `.out/x64-windows-Release/` | Compiled binaries |
| `.out/trace-nightly-*.exe` | NSIS installer |
| `.out/commit-hash` | Git commit hash of the build |

## Troubleshooting

### Visual Studio Not Found

**Error:** `Could not find MSVC Environment`

**Solution:** Ensure Visual Studio is installed with the "Desktop development with C++" workload. The builder uses `vswhere.exe` to locate VS installations.

### vcpkg Build Failures

**Error:** `Failure installing vcpkg ports`

**Solutions:**
1. Ensure you have enough disk space (~20 GB for vcpkg)
2. Check your internet connection
3. Try deleting the `vcpkg/` folder and running `-Vcpkg` again

### CMake Generation Failures

**Error:** `Failure generating cmake`

**Solutions:**
1. Ensure the Trace source is in the correct location (`../Trace/` relative to builder)
2. Check that vcpkg dependencies were built successfully
3. Try a clean build by deleting `.build/` and `.out/`

### Python/pip Errors

**Error:** `Error ensuring pip` or `Error installing wxpython requirements`

**Solutions:**
1. Ensure you're building for the same architecture as your host system
2. Check internet connectivity for pip downloads

### Path Too Long Errors

**Solution:** Enable long paths in Windows:
```powershell
# Run as Administrator
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
```

## Supported Architectures

| Architecture | Status | Notes |
|--------------|--------|-------|
| x64 | ✅ Fully supported | Primary target |
| x86 | ✅ Supported | 32-bit Windows |
| arm64 | ⚠️ Experimental | Limited Python support |

## CI/CD Integration

The repository includes Jenkins pipeline files:
- `Jenkinsfile` - Main build pipeline
- `Jenkinsfile.publish-s3` - S3 artifact publishing

These can be adapted for other CI systems (GitHub Actions, Azure Pipelines, etc.).

## Credits

This builder is based on the [KiCad Windows Builder](https://gitlab.com/kicad/packaging/kicad-win-builder), originally developed by:

- **Brian Sidebotham** - Started the win-builder in 2015
- **Nick Østergaard** - Maintained and expanded it during MSYS2 era
- **Mark Roszko** - Transitioned to MSVC builds with enhanced scripting

Adapted for Trace by the Trace Team.

## License

This project is licensed under the GNU General Public License v2.0 or later. See the [LICENSE](LICENSE) file for details.
