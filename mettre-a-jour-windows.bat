@echo off
rem Met a jour le site a partir du fichier Excel (double-clic, ou glisser le fichier Excel sur ce fichier).
chcp 65001 >nul
cd /d "%~dp0"

where git >nul 2>nul
if errorlevel 1 (
  echo Git est introuvable. Installez-le depuis https://git-scm.com/download/win puis relancez.
  pause
  exit /b 1
)
where ruby >nul 2>nul
if errorlevel 1 (
  echo Ruby est introuvable. Installez-le depuis https://rubyinstaller.org/ ^(version 3.x, sans DevKit^) puis relancez.
  pause
  exit /b 1
)

ruby -Eutf-8:utf-8 scripts\mettre-a-jour.rb %*
echo.
pause
