#!/bin/bash
# Doris GCP Cluster Scaling Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <environment> <count>"
    echo ""
    echo "Environments:"
    echo "  dev   - Development environment"
    echo "  sit   - System Integration Testing"
    echo "  uat   - User Acceptance Testing"
    echo "  prod  - Production environment"
    echo ""
    echo "Count: Number of BE instances to scale to"
    echo ""
    echo "Examples:"
    echo "  $0 dev 5      # Scale DEV to 5 BE instances"
    echo "  $0 prod 15    # Scale PROD to 15 BE instances"
    exit 1
}

if [ -z "$1" ] || [ -z "$2" ]; then
    usage
fi

ENVIRONMENT=$1
NEW_COUNT=$2
TFVARS_FILE="terraform.tfvars.${ENVIRONMENT}"

if ! [[ "$NEW_COUNT" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}Error: Invalid count '${NEW_COUNT}'${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Doris GCP Cluster Scaling${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Environment: ${ENVIRONMENT}${NC}"
echo -e "${YELLOW}New BE Count: ${NEW_COUNT}${NC}"
echo ""

# Get current configuration
CURRENT_MIN=$(grep "be_min_count" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' ')
CURRENT_MAX=$(grep "be_max_count" "$TFVARS_FILE" | cut -d'=' -f2 | tr -d ' ')

echo -e "${BLUE}Current Configuration:${NC}"
echo "  Min Count: $CURRENT_MIN"
echo "  Max Count: $CURRENT_MAX"
echo ""

if [ "$NEW_COUNT" -lt "$CURRENT_MIN" ]; then
    echo -e "${YELLOW}Warning: New count ($NEW_COUNT) is less than minimum ($CURRENT_MIN)${NC}"
    echo "Adjusting minimum count..."
    sed -i "s/be_min_count = $CURRENT_MIN/be_min_count = $NEW_COUNT/" "$TFVARS_FILE"
fi

if [ "$NEW_COUNT" -gt "$CURRENT_MAX" ]; then
    echo -e "${YELLOW}Warning: New count ($NEW_COUNT) is greater than maximum ($CURRENT_MAX)${NC}"
    echo "Adjusting maximum count..."
    sed -i "s/be_max_count = $CURRENT_MAX/be_max_count = $NEW_COUNT/" "$TFVARS_FILE"
fi

# Update be_count in tfvars
sed -i "s/be_count = .*/be_count = $NEW_COUNT/" "$TFVARS_FILE"

echo -e "${YELLOW}Applying scaling...${NC}"
terraform apply -auto-approve -var-file="$TFVARS_FILE"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Scaling completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}New Configuration:${NC}"
grep -E "be_count|be_min_count|be_max_count" "$TFVARS_FILE"
echo ""
