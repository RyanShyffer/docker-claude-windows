# Claude Code in a Windows Container

A Windows Server Core container with the .NET 10 SDK, Git, Node.js, the GitHub
CLI, and Claude Code preinstalled, configured to run Claude Code in YOLO mode
(`--dangerously-skip-permissions`) against the Lotus project
(`InstrumentControl-EMSLApp` / `LotusApp.sln`). The repo is bind-mounted at
`C:\workspace`, so Claude works on your real checkout — builds, test runs, and
edits all land on the host.

> **Machine-specific paths.** The bind mounts in `docker-compose.yml` (repo
> checkout, `Avery.Controls`, Basler Pylon SDK, personal skills) are hardcoded
> absolute paths for this machine (`C:\Development\...`), and
> `Claude YOLO (Lotus Container).lnk` is a shortcut pointing at
> `start-claude-yolo.ps1` on this machine. Anyone else using this repo will
> need to update those paths for their own checkout locations.

## Contents

| File | Purpose |
|---|---|
| `Dockerfile` | Builds the Windows Server Core image: .NET 10 SDK base, portable Git (+ Git Bash), Node.js, GitHub CLI, and Claude Code. |
| `docker-compose.yml` | Defines the `claude` service — bind mounts for the repo, `Avery.Controls`, and the Basler Pylon SDK, plus named volumes for Claude auth, NuGet cache, and app config. |
| `start-claude-yolo.ps1` | One-shot launcher: starts Docker Desktop, switches to Windows containers mode, builds the image if missing, and drops you into Claude Code with permission prompts disabled. |
| `Claude YOLO (Lotus Container).lnk` | Windows shortcut to the launcher script above, for double-click launching. |
| `README.md` | This file. |

## What works / what doesn't

| Capability | Status |
|---|---|
| `dotnet build` / `dotnet test` of `LotusApp.sln` | ✅ works (private feed creds come from the repo's committed `NuGet.config`) |
| Running the app headless (logs, service startup, mock hardware fallbacks) | ✅ starts, but **no visible UI** — Server Core containers have no desktop session |
| Debugging via Claude (build, run tests, read Serilog output, bisect) | ✅ |
| Seeing the Avalonia GUI | ❌ not possible in a Windows container; run the app on the host for visual checks |
| LAN hardware / PostgreSQL (`lab-mini-2`) | ✅ reachable via container NAT (if the host can reach it) |
| USB devices (cameras, Keithley over USB) | ❌ no USB passthrough; network-attached instruments only |

## Prerequisites

`LotusApp.sln` references the sibling repo `..\Avery.Controls`, so a checkout
must exist next to this repo (e.g. `C:\Development\Avery.Controls`). The
compose file bind-mounts it to `C:\Avery.Controls` in the container, which is
where the solution's relative reference resolves from `C:\workspace`.

## One-time host setup

1. Docker Desktop must be in **Windows containers** mode:

   ```powershell
   & "C:\Program Files\Docker\Docker\DockerCli.exe" -SwitchWindowsEngine
   ```

   (Switch back with `-SwitchLinuxEngine`. The first switch may prompt to
   enable the Windows *Containers* feature, which needs a reboot.)

2. Build the image (~15–30 min first time; the Server Core base is a few GB):

   ```powershell
   cd docker\claude-windows
   docker compose build
   ```

## Running Claude

```powershell
cd docker\claude-windows
docker compose run --rm claude        # lands in PowerShell at C:\workspace
claude                                # start Claude Code
```

Or use the one-shot launcher, which starts Docker Desktop, switches to
Windows containers, builds the image if missing, and starts Claude with
permission prompts disabled (`--dangerously-skip-permissions`):

```powershell
.\docker\claude-windows\start-claude-yolo.ps1          # -Rebuild to force image rebuild
```

YOLO caveats: the repo and `Avery.Controls` are bind-mounted read-write and
the container has LAN access (database, network instruments), so commit/push
before running and unplug/power off instruments you don't want touched.

First run: either export `ANTHROPIC_API_KEY` in the host shell before
`docker compose run` (headless auth), or just run `claude` and follow the
OAuth URL in a host browser, then paste the code back. Credentials persist in
the `claude-config` named volume, so login is one-time.

Non-interactive one-shots also work:

```powershell
docker compose run --rm claude claude -p "build LotusApp.sln and summarize any errors"
```

## Sanity checks inside the container

```powershell
dotnet build LotusApp.sln
dotnet test LotusApp.sln
claude --version
```

## Notes

- **Isolation:** `docker-compose.yml` pins `isolation: hyperv`. The host
  (Windows 11 build 26200) and the `ltsc2025` image (build 26100) don't match,
  so process isolation cannot be used.
- **Memory:** Hyper-V containers get 1 GB by default; compose raises it to
  12 GB (`mem_limit`). Lower it if the host is tight on RAM.
- **Claude updates:** the auto-updater is disabled inside the image
  (`DISABLE_AUTOUPDATER=1`). To update:
  `docker compose build --no-cache claude` (or `npm i -g @anthropic-ai/claude-code` inside a running container for a throwaway upgrade).
- **App config:** `C:\Avery` is a named volume, so config generated by
  `ConfigManager` on first run persists across container recreations. Delete
  the `avery-config` volume to reset to defaults.
- **Basler Pylon:** `Devices.csproj` references `Basler.Pylon.dll` from the
  SDK install path, so the compose file mounts the host's
  `C:\Program Files\Basler\pylon` read-only at the same path in the container.
  The host must have the Pylon SDK installed for the solution to compile.
- **Skills:** `C:\Development\AiSkills` on the host is bind-mounted to
  `C:\claude-config\skills` (nested under the `claude-config` volume, since
  `CLAUDE_CONFIG_DIR=C:\claude-config`), so Claude inside the container sees
  the same personal skills as the host install. Edits to skills on the host
  take effect immediately, no rebuild needed.
- **PowerShell:** the container has Windows PowerShell 5.1 (`powershell`), not
  pwsh 7. That's fine for Claude Code; its Bash tool uses the bundled Git Bash.
