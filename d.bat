@echo off

setlocal

set "ProductName=ClipFlow"
set "ZipFileNameFree=ClipFlowFree.zip"
set "ZipFileNamePro=ClipFlowPro.zip"
set "ExeFileName=clipflow.exe"
set "LicenseFile=LICENSE"
set "LicenseAssetsFile=LICENSE-ASSETS"
set "ReadmeFile=README.html"

set "RepoRoot=%~dp0"
set "RepoRootNoTrailingSlash=%RepoRoot:~0,-1%"
set "BuildDir=%RepoRoot%build"
set "DistDir=%RepoRoot%dist"
set "UserDocDir=%RepoRoot%doc\user"

if exist "%BuildDir%" (
    echo Rebuilding %ProductName%...
    call "%RepoRoot%clean.bat"
    if errorlevel 1 exit /b 1
) else (
    echo Building %ProductName%...
)

call "%RepoRoot%clean.bat"
if errorlevel 1 exit /b 1

call "%RepoRoot%build.bat"
if errorlevel 1 exit /b 1

if exist "%DistDir%" rd /s /q "%DistDir%"
if errorlevel 1 exit /b 1

md "%DistDir%"
if errorlevel 1 exit /b 1

call :Package "free" "Free" "%ZipFileNameFree%"
if errorlevel 1 exit /b 1

call :Package "pro" "Pro" "%ZipFileNamePro%"
if errorlevel 1 exit /b 1

exit /b 0

:Package
set "Edition=%~1"
set "DisplayName=%~2"
set "ZipFileName=%~3"

echo Packaging %ProductName% %DisplayName%...

tar -a -cf "%DistDir%\%ZipFileName%" ^
    -C "%RepoRootNoTrailingSlash%" "%LicenseFile%" "%LicenseAssetsFile%" ^
    -C "%BuildDir%\%Edition%" "%ExeFileName%" ^
    -C "%UserDocDir%\%Edition%" "%ReadmeFile%"
if errorlevel 1 exit /b 1

exit /b 0
