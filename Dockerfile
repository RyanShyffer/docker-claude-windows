# escape=`

# Windows container for running Claude Code against the Lotus solution.
# Base: .NET 10 SDK on Windows Server Core LTSC2025.
# On a Windows 11 client host this runs under Hyper-V isolation (the Docker
# Desktop default when the host build differs from the image build).
ARG BASE_TAG=10.0-windowsservercore-ltsc2025
FROM mcr.microsoft.com/dotnet/sdk:${BASE_TAG}

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# --- Portable Git (full Git for Windows incl. bash + unix tools; Claude Code requires Git Bash on Windows)
ARG GIT_VERSION=2.49.0
RUN Invoke-WebRequest -Uri ('https://github.com/git-for-windows/git/releases/download/v{0}.windows.1/PortableGit-{0}-64-bit.7z.exe' -f $env:GIT_VERSION) -OutFile C:\git-portable.exe; `
    Start-Process C:\git-portable.exe -ArgumentList '-o', 'C:\git', '-y' -Wait; `
    Remove-Item C:\git-portable.exe

# The repo is bind-mounted from the host, so its on-disk owner never matches
# the container user — mark everything safe and enable long paths.
RUN C:\git\cmd\git.exe config --system --add safe.directory '*'; `
    C:\git\cmd\git.exe config --system core.longpaths true

# --- Node.js LTS (runtime for the npm-distributed Claude Code build)
ARG NODE_VERSION=22.17.0
RUN Invoke-WebRequest -Uri ('https://nodejs.org/dist/v{0}/node-v{0}-x64.msi' -f $env:NODE_VERSION) -OutFile C:\node.msi; `
    Start-Process msiexec.exe -ArgumentList '/i', 'C:\node.msi', '/qn', '/norestart' -Wait; `
    Remove-Item C:\node.msi

# --- GitHub CLI (Claude Code uses `gh` for PRs/issues; authenticate via GH_TOKEN at runtime)
ARG GH_VERSION=2.63.0
RUN Invoke-WebRequest -Uri ('https://github.com/cli/cli/releases/download/v{0}/gh_{0}_windows_amd64.zip' -f $env:GH_VERSION) -OutFile C:\gh.zip; `
    Expand-Archive C:\gh.zip -DestinationPath C:\gh; `
    Remove-Item C:\gh.zip

# --- Claude Code (installed to a fixed machine-wide prefix so it survives volume mounts over the user profile)
RUN npm config set prefix C:\npm --location=global; `
    npm install -g @anthropic-ai/claude-code

# Machine PATH: node's MSI already added itself; append git, gh, and the npm prefix.
RUN setx /M PATH ($env:PATH + ';C:\git\cmd;C:\git\bin;C:\git\usr\bin;C:\gh\bin;C:\npm')

ENV CLAUDE_CODE_GIT_BASH_PATH="C:\git\bin\bash.exe" `
    CLAUDE_CONFIG_DIR="C:\claude-config" `
    DISABLE_AUTOUPDATER=1 `
    NUGET_PACKAGES="C:\nuget-packages" `
    DOTNET_CLI_TELEMETRY_OPTOUT=1 `
    DOTNET_NOLOGO=1

WORKDIR C:\workspace

CMD ["powershell"]
