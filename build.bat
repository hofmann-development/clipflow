@echo off

setlocal

set "ProductName=ClipFlow"
set "ResourceFileName=clipflow.rc"
set "CompiledResourceFileName=clipflow.res"
set "SourceFileName=clipflow.asm"
set "ObjectFileName=clipflow.obj"
set "ExeFileName=clipflow.exe"

set "RepoRoot=%~dp0"
set "BuildDir=%RepoRoot%build"

call :Build "free" "Free" "-DFREE_VERSION" "/dFREE_VERSION"
if errorlevel 1 exit /b 1

call :Build "pro" "Pro" "" ""
if errorlevel 1 exit /b 1

echo Done.

exit /b 0

:Build
set "Edition=%~1"
set "DisplayName=%~2"
set "ExtraAssemblerDefines=%~3"
set "ExtraResourceDefines=%~4"
set "OutputDir=%BuildDir%\%Edition%"

if not exist "%OutputDir%" (
    md "%OutputDir%" 
    if errorlevel 1 exit /b 1
)

echo Building %ProductName% %DisplayName%...

jwasm -nologo ^
    -I%USERPROFILE%\WinInc\Include ^
    -win64 ^
    -Zp8 ^
    %ExtraAssemblerDefines% ^
    -Fo%OutputDir%\%ObjectFileName% ^
    %SourceFileName%
if errorlevel 1 exit /b 1

rc /nologo %ExtraResourceDefines% /fo %OutputDir%\%CompiledResourceFileName% %ResourceFileName%
if errorlevel 1 exit /b 1

link /nologo ^
    /subsystem:windows ^
    /out:%OutputDir%\%ExeFileName% ^
    %OutputDir%\%ObjectFileName% ^
    %OutputDir%\%CompiledResourceFileName%
if errorlevel 1 exit /b 1

exit /b 0
