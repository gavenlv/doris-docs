@echo off
REM Doris GCP Cluster Deployment Script for Windows

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
    echo Examples:
    echo   %0 dev
    echo   %0 prod
    exit /b 1
)

set ENVIRONMENT=%1
set TFVARS_FILE=terraform.tfvars.%ENVIRONMENT%

echo ========================================
echo Doris GCP Cluster Deployment
echo ========================================
echo Environment: %ENVIRONMENT%
echo Config File: %TFVARS_FILE%
echo.

REM Check if tfvars file exists
if not exist "%TFVARS_FILE%" (
    echo Error: Configuration file '%TFVARS_FILE%' not found
    exit /b 1
)

REM Initialize Terraform
echo [1/4] Initializing Terraform...
terraform init

REM Validate configuration
echo [2/4] Validating configuration...
terraform validate -var-file="%TFVARS_FILE%"

REM Plan deployment
echo [3/4] Planning deployment...
terraform plan -var-file="%TFVARS_FILE%" -out=tfplan

REM Ask for confirmation
set /p confirm="Do you want to proceed with the deployment? (yes/no): "
if not "%confirm%"=="yes" (
    echo Deployment cancelled.
    exit /b 0
)

REM Apply changes
echo [4/4] Applying changes...
terraform apply tfplan

REM Cleanup
if exist tfplan del tfplan

echo.
echo ========================================
echo Deployment completed successfully!
echo ========================================
echo.
echo To view outputs:
echo   terraform output -json
echo.
echo To destroy the cluster:
echo   destroy.bat %ENVIRONMENT%
echo.

endlocal
