@echo off
echo -----------------------------
echo installing prerequisites

echo Creating virtual environment for the project...
python -m venv .venv --prompt VirtualEnv
timeout -t 2

echo Activating environment...
call .venv\Scripts\activate.bat
timeout -t 2

  echo Upgrading PIP itself in venv...
  python -m pip install --upgrade pip
  python -m pip install wheel
 
  timeout -t 2

  echo Installing prerequisites to virtual environment...
  rem python -m pip install "Flask[async]"
  python -m pip install Quart
  timeout -t 5
  rem python -m pip install websockets
  rem timeout -t 5
  rem python -m pip install json2xml
  rem timeout -t 5
  rem python -m pip install aiohttp
  rem timeout -t 5
  python -m pip install lxml
  timeout -t 5
  python -m pip install pyyaml
  timeout -t 5

echo Deactivating environment...
call .venv\Scripts\deactivate.bat
timeout -t 2
echo -----------------------------
