:: -------------------------------------------------------
:: 2. VHD 복사 (별도 창에서 진행률 표시 + 완료 대기)
:: -------------------------------------------------------
echo [STEP 2] VHD 복사 중...
if not exist "%SRC_VHD%" (
  echo [ERROR] 원본 VHD 파일이 없습니다: %SRC_VHD%
  pause
  exit /b
)
if not exist "%DST_VHD_DIR%" mkdir "%DST_VHD_DIR%" >nul 2>&1

for %%F in ("%SRC_VHD%") do (
  set "SRC_DIR=%%~dpF"
  set "SRC_NAME=%%~nxF"
)

echo [INFO] robocopy 별도 콘솔에서 복사 시작: !SRC_DIR!!SRC_NAME! → %DST_VHD_DIR%
echo [INFO] 복사 창이 자동으로 닫히면 다음 단계로 진행합니다.
echo.
timeout /t 2 >nul

:: robocopy 실행용 임시 스크립트 생성
set "RC_SCRIPT=%TEMP%\run_robocopy_%RANDOM%.cmd"
(
  echo @echo off
  echo title VHD 복사 중 - robocopy
  echo color 0A
  echo echo [INFO] 복사 시작: %%date%% %%time%%
  echo echo 원본: "%SRC_VHD%"
  echo echo 대상: "%DST_VHD_DIR%\%SRC_NAME%"
  echo echo.
  echo robocopy "%SRC_DIR%" "%DST_VHD_DIR%" "%SRC_NAME%" /ETA /R:1 /W:1 /NFL /NDL /TEE /LOG+:"%TEMP%\robocopy.log"
  echo echo.
  echo echo [INFO] 복사 완료! 이 창은 자동으로 닫힙니다.
  echo timeout /t 2 ^>nul
) > "%RC_SCRIPT%"

:: robocopy를 새 콘솔 창에서 실행
start "VHD_COPY_WINDOW" cmd /c "%RC_SCRIPT%"

:: robocopy 창이 닫힐 때까지 대기
:WAIT_COPY
timeout /t 2 >nul
tasklist /FI "WINDOWTITLE eq VHD 복사 중 - robocopy" | find "cmd.exe" >nul
if %errorlevel%==0 goto WAIT_COPY

del "%RC_SCRIPT%" >nul 2>&1

:: robocopy 로그에서 오류 코드 확인 (선택 사항)
findstr /C:"ERROR" "%TEMP%\robocopy.log" >nul 2>&1
if %errorlevel%==0 (
  echo [경고] robocopy 로그에서 오류 감지됨. 로그 확인: %TEMP%\robocopy.log
) else (
  echo [OK] VHD 복사 완료.
)
echo.
