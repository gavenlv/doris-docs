#!/bin/bash
# Doris GCP Cluster Scaling Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Usage function
usage() {
    echo "Usage: $0 <environment> <action> <count>"
    echo ""
    echo "Environments:"
    echo "  dev   - Development environment"
    echo "  sit   - System Integration Testing"
    echo "  uat   - User Acceptance Testing"
    echo "  prod  - Production environment"
    echo ""
    echo "Actions:"
    echo "  up     - Scale up BE instances"
    echo "  down   - Scale down BE instances"
    echo "  set    - Set exact BE instance count"
    echo ""
    echo "Count:"
    echo "  Number of BE instances"
    echo ""
    echo "Examples:"
    echo "  $0 prod up 3       # Scale up by 3 instances"
    echo "  $0 prod down 2     # Scale down by 2 instances"
    echo "  $0 prod set 10     # Set to 10 instances"
    echo ""
    echo "Note: If autoscaling is enabled, use Instance Group Manager API directly."
    exit 1
}

# Check arguments
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    usage
fi

ENVIRONMENT=$1
ACTION=$2
COUNT=$3
TFVARS_FILE="terraform.tfvars.${ENVIRONMENT}"

# Validate environment
case $ENVIRONMENT in
    dev|sit|uat|prod)
        ;;
    *)
        echo -e "${RED}Error: Invalid environment '${ENVIRONMENT}'${NC}"
        exit 1
        ;;
esac

# Validate action
case $ACTION in
    up|down|set)
        ;;
    *)
        echo -e "${RED}Error: Invalid action '${ACTION}'${NC}"
        echo "Valid actions: up, down, set"
        exit 1
        ;;
esac

# Validate count
if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Invalid count '${COUNT}'${NC}"
    echo "Count must be a positive integer"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Doris GCP Cluster Scaling${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Environment: ${ENVIRONMENT}${NC}"
echo -e "${YELLOW}Action: ${ACTION} ${COUNT}${NC}"
echo ""

# Get current BE count
CURRENT_COUNT=$(terraform output -json cluster_info | jq -r '.be_count')
echo -e "${YELLOW}Current BE count: ${CURRENT_COUNT}${NC}"

# Calculate new count
case $ACTION in
    up)
        NEW_COUNT=$((CURRENT_COUNT + COUNT))
        ;;
    down)
        NEW_COUNT=$((CURRENT_COUNT - COUNT))
        if [ $NEW_COUNT -lt 1 ]; then
            echo -e "${RED}Error: BE count cannot be less than 1${NC}"
            exit 1
        fi
        ;;
    set)
        NEW_COUNT=$COUNT
        ;;
esac

echo -e "${YELLOW}New BE count: ${NEW_COUNT}${NC}"
echo ""

# Apply scaling
echo -e "${YELLOW}Applying scaling...${NC}"
terraform apply -auto-approve -var-file="$TFVARS_FILE" -var "be_count=$NEW_COUNT"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Scaling completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Monitoring scaling progress:"
echo "  terraform output -json | jq '.be_ips'"
echo ""
