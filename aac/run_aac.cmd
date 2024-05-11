@echo off
rem if "%1"=="" echo Please specify RUNAT option! & exit 1

if not exist .venv call initial_setup.cmd

echo Entering virtual environment...
call .venv\Scripts\activate.bat
timeout -t 1

set RUNOPTION=
if not "%1"=="" set RUNOPTION=-runat=%1

echo Running using internal startup code
python aac.py %RUNOPTON%

timeout -t 1

echo Leaving virtual environment...
call .venv\Scripts\deactivate.bat
timeout -t 5
