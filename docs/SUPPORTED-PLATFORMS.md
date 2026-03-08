# Supported Platforms

## Currently Supported

| Machine        | Architecture           | Docker Platform | Status     |
|----------------|------------------------|-----------------|------------|
| Raspberry Pi 5 | ARMv8.2-A / Cortex-A76 | `linux/arm64`   | **Active** |

## Planned

| Machine          | Architecture         | Docker Platform | Phase |
|------------------|----------------------|-----------------|-------|
| Raspberry Pi 4   | ARMv8-A / Cortex-A72 | `linux/arm64`   | 2     |
| Raspberry Pi 2   | ARMv7 / Cortex-A7    | `linux/arm/v7`  | 2     |
| BeagleBone Black | ARMv7 / Cortex-A8    | `linux/arm/v7`  | 3     |
| NanoPi           | ARMv8                | `linux/arm64`   | 3     |
| Einstein (Sunxi) | ARMv7                | `linux/arm/v7`  | 3     |
| Ekrano GX        | ARMv8                | `linux/arm64`   | 3     |
| Color Control GX | ARMv7                | `linux/arm/v7`  | 3     |

## Venus OS Release Feeds

Images are available from multiple release channels:

| Feed        | Description                | Stability   |
|-------------|----------------------------|-------------|
| `release`   | Stable releases            | Production  |
| `candidate` | Release candidates         | Testing     |
| `testing`   | Beta builds                | Development |
| `develop`   | Nightly/latest development | Unstable    |

Default: `release`

## Adding a New Platform

To add support for a new machine:

1. Verify the machine name exists in Victron's image repository
2. Add the entry to `config/machines.json`
3. Test the download, extraction, and build pipeline
4. Adjust `scripts/modify-rootfs.sh` if machine-specific patches are needed
5. Add to the GitHub Actions matrix in `.github/workflows/`
