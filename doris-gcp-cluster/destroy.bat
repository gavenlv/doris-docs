@echo off
REM Doris GCP Cluster Destruction Script for Windows

setlocal enabledelayedexpansion

if "%1"=="" (
    echo Usage: %0 ^<environment^>
    echo.
    echo Environments:
    echo   dev   - Development environment
    echo   sit   - System Integration Testing
    echo   uat   - User Acceptance Testing
    echo   prod  - Production environment
    echo.
    echo Note: Persistent disks and GCS buckets will be preserved.
    echo       Use 'clean-all.bat' to remove all resources including data.
    echo.
    echo Examples:
    echo   %0 dev
    echo   %0 prod
    exit /b 1
)

set ENVIRONMENT=%1
set TFVARS_FILE=terraform.tfvars.%ENVIRONMENT%

echo ========================================
echo Doris GCP Cluster Destruction
echo ========================================
echo Environment: %ENVIRONMENT%
echo Config File: %TFVARS_FILE%
echo.
echo Warning: This will destroy all compute instances but preserve persistent disks and GCS buckets.
echo.

REM Confirm destruction
set /p confirm="Are you sure you want to destroy the cluster? (yes/no): "
if not "%confirm%"=="yes" (
    echo Destruction cancelled.
    exit /b 0
)

REM Initialize Terraform
echo [1/2] Initializing Terraform...
terraform init

REM Destroy resources
echo [2/2] Destroying cluster...
terraform destroy -var-file="%TFVARS_FILE%" -auto-approve

echo.
echo ========================================
echo Cluster destroyed successfully!
echo ========================================
echo.
echo Persistent disks and GCS buckets have been preserved.
echo To permanently delete them, use:
echo   clean-all.bat %ENVIRONMENT%
echo.

endlocal
