#!/bin/bash
# Upload Installation Artifacts to GCS Bucket
# Run this script from a machine with internet access BEFORE deploying the cluster

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <environment>"
    echo ""
    echo "Environments:"
    echo "  dev   - Development environment"
    echo "  sit   - System Integration Testing"
    echo "  uat   - User Acceptance Testing"
    echo "  prod  - Production environment"
    echo ""
    echo "Prerequisites:"
    echo "  1. Run from a machine with internet access"
    echo "  2. gcloud CLI installed and authenticated"
    echo "  3. Terraform initialized (to get bucket name)"
    echo ""
    exit 1
}

if [ -z "$1" ]; then
    usage
fi

ENVIRONMENT=$1
TFVARS_FILE="terraform.tfvars.${ENVIRONMENT}"

if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "${RED}Error: Configuration file '$TFVARS_FILE' not found${NC}"
    exit 1
fi

# Extract bucket name from tfvars
GCS_BUCKET=$(grep "gcs_bucket_name" "$TFVARS_FILE" | cut -d'"' -f2)
ARTIFACTS_BUCKET="${GCS_BUCKET}-artifacts"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Upload Installation Artifacts${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Environment: ${ENVIRONMENT}${NC}"
echo -e "${YELLOW}Artifacts Bucket: ${ARTIFACTS_BUCKET}${NC}"
echo ""

# Check if bucket exists
echo -e "${BLUE}[1/6] Checking GCS bucket...${NC}"
if ! gsutil ls "gs://${ARTIFACTS_BUCKET}" > /dev/null 2>&1; then
    echo -e "${YELLOW}Bucket does not exist. Creating...${NC}"
    gsutil mb -l us-central1 "gs://${ARTIFACTS_BUCKET}"
    gsutil uniformbucketlevelaccess set on "gs://${ARTIFACTS_BUCKET}"
fi

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

cd "$TEMP_DIR"

# Download Doris packages
echo -e "${BLUE}[2/6] Downloading Doris packages...${NC}"
DORIS_VERSION="4.0.2"
DORIS_MIRROR="https://archive.apache.org/dist/doris"

FE_PACKAGE="apache-doris-fe-${DORIS_VERSION}-bin-x86_64.tar.gz"
BE_PACKAGE="apache-doris-be-${DORIS_VERSION}-bin-x86_64.tar.gz"

if [ ! -f "$FE_PACKAGE" ]; then
    echo "  Downloading ${FE_PACKAGE}..."
    wget -q --show-progress "${DORIS_MIRROR}/${DORIS_VERSION}/${FE_PACKAGE}" -O "$FE_PACKAGE"
fi

if [ ! -f "$BE_PACKAGE" ]; then
    echo "  Downloading ${BE_PACKAGE}..."
    wget -q --show-progress "${DORIS_MIRROR}/${DORIS_VERSION}/${BE_PACKAGE}" -O "$BE_PACKAGE"
fi

echo -e "${GREEN}  ✓ Doris packages downloaded${NC}"

# Download FoundationDB packages
echo -e "${BLUE}[3/6] Downloading FoundationDB packages...${NC}"
FDB_VERSION="7.3.27"
FDB_BASE_URL="https://github.com/apple/foundationdb/releases/download/${FDB_VERSION}"

FDB_CLIENT_PKG="foundationdb-clients_${FDB_VERSION}-1_amd64.deb"
FDB_SERVER_PKG="foundationdb-server_${FDB_VERSION}-1_amd64.deb"

if [ ! -f "$FDB_CLIENT_PKG" ]; then
    echo "  Downloading ${FDB_CLIENT_PKG}..."
    wget -q --show-progress "${FDB_BASE_URL}/${FDB_CLIENT_PKG}" -O "$FDB_CLIENT_PKG"
fi

if [ ! -f "$FDB_SERVER_PKG" ]; then
    echo "  Downloading ${FDB_SERVER_PKG}..."
    wget -q --show-progress "${FDB_BASE_URL}/${FDB_SERVER_PKG}" -O "$FDB_SERVER_PKG"
fi

echo -e "${GREEN}  ✓ FoundationDB packages downloaded${NC}"

# Download gcsfuse
echo -e "${BLUE}[4/6] Downloading gcsfuse...${NC}"
GCSFUSE_PKG="gcsfuse_latest_amd64.deb"
GCSFUSE_URL="https://github.com/GoogleCloudPlatform/gcsfuse/releases/download/v2.0.1/gcsfuse_2.0.1_amd64.deb"

if [ ! -f "$GCSFUSE_PKG" ]; then
    echo "  Downloading ${GCSFUSE_PKG}..."
    wget -q --show-progress "$GCSFUSE_URL" -O "$GCSFUSE_PKG"
fi

echo -e "${GREEN}  ✓ gcsfuse downloaded${NC}"

# Upload to GCS
echo -e "${BLUE}[5/6] Uploading artifacts to GCS...${NC}"

echo "  Uploading Doris packages..."
gsutil -h "Cache-Control: public, max-age=3600" cp "$FE_PACKAGE" "gs://${ARTIFACTS_BUCKET}/doris/"
gsutil -h "Cache-Control: public, max-age=3600" cp "$BE_PACKAGE" "gs://${ARTIFACTS_BUCKET}/doris/"

echo "  Uploading FoundationDB packages..."
gsutil -h "Cache-Control: public, max-age=3600" cp "$FDB_CLIENT_PKG" "gs://${ARTIFACTS_BUCKET}/foundationdb/"
gsutil -h "Cache-Control: public, max-age=3600" cp "$FDB_SERVER_PKG" "gs://${ARTIFACTS_BUCKET}/foundationdb/"

echo "  Uploading gcsfuse..."
gsutil -h "Cache-Control: public, max-age=3600" cp "$GCSFUSE_PKG" "gs://${ARTIFACTS_BUCKET}/tools/"

echo -e "${GREEN}  ✓ All artifacts uploaded${NC}"

# Verify upload
echo -e "${BLUE}[6/6] Verifying uploaded artifacts...${NC}"
echo ""
echo "Artifacts in bucket:"
gsutil ls -r "gs://${ARTIFACTS_BUCKET}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Artifacts upload completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Artifacts Bucket:${NC} gs://${ARTIFACTS_BUCKET}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Ensure VMs have access to this bucket via VPC"
echo "  2. Deploy the cluster: ./deploy.sh ${ENVIRONMENT}"
echo ""
