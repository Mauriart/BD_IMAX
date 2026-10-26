@echo off
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo Primero prepara las dependencias siguiendo dependencias.md.
    pause
    exit /b 1
)
if not exist ".env" (
    echo Primero ejecuta .venv\Scripts\python.exe instalar.py
    pause
    exit /b 1
)
".venv\Scripts\python.exe" iniciar.py
if errorlevel 1 pause
