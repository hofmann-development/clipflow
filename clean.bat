@echo off

setlocal

set "RepoRoot=%~dp0"
set "BuildDir=%RepoRoot%build"

if exist "%BuildDir%" (
    echo Deleting build directory...
    rd /s /q "%BuildDir%"
    if errorlevel 1 exit /b 1
)

exit /b 0
