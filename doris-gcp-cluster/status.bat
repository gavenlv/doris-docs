@echo off
REM Doris GCP Cluster Status Script for Windows

setlocal enabledelayedexpansion

if not exist "terraform.tfstate" (
    echo Error: Terraform state file not found
    echo Run 'terraform init' and deploy the cluster first
    exit /b 1
)

echo ========================================
echo Doris GCP Cluster Status
echo ========================================
echo.

echo [Cluster Configuration]
terraform output -json cluster_info
echo.

echo [FE Instances]
terraform output -json fe_ips
echo.

echo [BE Instances]
terraform output -json be_ips
echo.

echo [Load Balancer]
terraform output -json lb_internal_ip
echo.

echo [Persistent Disks]
terraform output -json persistent_disks
echo.

echo [Storage Configuration]
terraform output -json gcs_bucket
echo.

echo ========================================
echo For detailed instance status, run:
echo   gcloud compute instances list --filter="name~doris*"
echo ========================================
echo.

endlocal
