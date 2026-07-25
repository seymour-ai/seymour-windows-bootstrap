# Seymour Windows Bootstrap

Public bootstrapper for installing Seymour Fleet on a Windows host without requiring Git or Python to be preinstalled.

Run from PowerShell:

```powershell
$script = "$env:TEMP\install-seymour.ps1"; Invoke-WebRequest "https://raw.githubusercontent.com/seymour-ai/seymour-windows-bootstrap/main/install.ps1" -OutFile $script; powershell -ExecutionPolicy Bypass -File $script
```

The script installs missing prerequisites with `winget`, clones or updates the private Seymour Fleet repo, and runs the Windows local test flow. Access to the private repo still requires GitHub authentication when Git clones `seymour-ai/seymour-fleet`.
