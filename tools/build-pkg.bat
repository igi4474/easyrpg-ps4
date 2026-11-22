@echo off
rem Packs every sub-folder that contains an app.gp4 (e.g. EasyRPG\) into a PS4 .pkg
rem using LibOrbisPkg's PkgTool.exe (https://github.com/maxton/LibOrbisPkg/releases, v0.2).
rem Put PkgTool.exe + its .dll files next to this script.
cd /d "%~dp0"
if not exist PkgTool.exe (
  echo PkgTool.exe not found next to this script.
  pause
  exit /b 1
)
for /d %%A in (*) do (
  if exist "%%A\app.gp4" (
    echo === %%A ===
    pushd "%%A"
    ..\PkgTool.exe pkg_build app.gp4 ..
    popd
  )
)
echo.
echo Done. The .pkg file^(s^) are in this folder.
pause
