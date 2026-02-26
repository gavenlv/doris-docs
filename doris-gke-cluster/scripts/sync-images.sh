#!/bin/bash

# ==========================================
# Doris GKE Cluster - Image Sync Script
# ==========================================
# Purpose: Sync Docker images from official registries to Nexus
# Version: 1.0
# Last Updated: 2026-02-26

set -e  # Exit on error

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(cd "${SCRIPT_DIR}/../configs" && pwd)"
IMAGES_LIST="${CONFIG_DIR}/images-list.txt"
NEXUS_CONFIG="${CONFIG_DIR}/nexus-config.yaml"

# Nexus settings (can be overridden by environment variables)
NEXUS_URL="${NEXUS_URL:-nexus.company.com}"
NEXUS_USER="${NEXUS_USER:-admin}"
NEXUS_PASS="${NEXUS_PASS:-password}"
NEXUS_REPO="${NEXUS_REPO:-doris}"

# ==========================================
# Color Output
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ==========================================
# Functions
# ==========================================

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if [ ! -f "$IMAGES_LIST" ]; then
        log_error "Images list file not found: $IMAGES_LIST"
        exit 1
    fi
    
    log_info "Prerequisites check passed."
}

# Login to Nexus
login_nexus() {
    log_info "Logging in to Nexus registry: $NEXUS_URL"
    
    echo "$NEXUS_PASS" | docker login "$NEXUS_URL" \
        --username "$NEXUS_USER" \
        --password-stdin
    
    if [ $? -eq 0 ]; then
        log_info "Successfully logged in to Nexus"
    else
        log_error "Failed to login to Nexus. Check your credentials."
        exit 1
    fi
}

# Sync a single image
sync_image() {
    local source_image="$1"
    local target_image="$2"
    
    log_info "Syncing image: $source_image -> $target_image"
    
    # Pull from source
    log_info "Pulling $source_image..."
    if ! docker pull "$source_image"; then
        log_error "Failed to pull $source_image"
        return 1
    fi
    
    # Tag for Nexus
    log_info "Tagging as $target_image..."
    if ! docker tag "$source_image" "$target_image"; then
        log_error "Failed to tag $source_image as $target_image"
        return 1
    fi
    
    # Push to Nexus
    log_info "Pushing to Nexus..."
    if ! docker push "$target_image"; then
        log_error "Failed to push $target_image to Nexus"
        return 1
    fi
    
    # Clean up local images (optional)
    log_info "Cleaning up local images..."
    docker rmi "$source_image" "$target_image" 2>/dev/null || true
    
    log_info "Successfully synced: $source_image"
    return 0
}

# Parse image name and create Nexus target
parse_image_name() {
    local source_image="$1"
    
    # Extract image name and tag
    local image_name=$(echo "$source_image" | cut -d':' -f1 | rev | cut -d'/' -f1 | rev)
    local tag=$(echo "$source_image" | cut -d':' -f2)
    
    # Create Nexus target
    local target_image="${NEXUS_URL}/${NEXUS_REPO}/${image_name}:${tag}"
    
    echo "$target_image"
}

# Main sync process
sync_all_images() {
    log_info "Starting image synchronization..."
    log_info "Source: Official Docker Registries"
    log_info "Target: $NEXUS_URL/$NEXUS_REPO"
    echo ""
    
    local total=0
    local success=0
    local failed=0
    
    # Read images from list (skip comments and empty lines)
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]]; then
            continue
        fi
        
        # Trim whitespace
        line=$(echo "$line" | xargs)
        
        ((total++))
        
        # Parse and sync image
        target_image=$(parse_image_name "$line")
        
        if sync_image "$line" "$target_image"; then
            ((success++))
        else
            ((failed++))
        fi
        
        echo ""
    done < "$IMAGES_LIST"
    
    # Summary
    log_info "========================================="
    log_info "Sync Summary:"
    log_info "  Total images: $total"
    log_info "  Successful: $success"
    if [ $failed -gt 0 ]; then
        log_error "  Failed: $failed"
    fi
    log_info "========================================="
    
    if [ $failed -gt 0 ]; then
        return 1
    fi
    
    return 0
}

# ==========================================
# Main Execution
# ==========================================

main() {
    log_info "Doris GKE Cluster - Image Sync Tool"
    log_info "========================================="
    echo ""
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    # Login to Nexus
    login_nexus
    echo ""
    
    # Sync all images
    sync_all_images
    
    log_info "Image synchronization completed!"
}

# Run main function
main "$@"
