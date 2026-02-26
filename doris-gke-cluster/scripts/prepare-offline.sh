#!/bin/bash

# ==========================================
# Doris GKE Cluster - Offline Deployment Preparation Script
# ==========================================
# Purpose: Prepare images for offline deployment
# Version: 1.0
# Last Updated: 2026-02-26

set -e

# ==========================================
# Configuration
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(cd "${SCRIPT_DIR}/../configs" && pwd)"
IMAGES_LIST="${CONFIG_DIR}/images-list.txt"
OFFLINE_DIR="${SCRIPT_DIR}/../offline-images"

# ==========================================
# Color Output
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Create offline images directory
create_offline_dir() {
    log_info "Creating offline images directory: $OFFLINE_DIR"
    mkdir -p "$OFFLINE_DIR"
}

# Pull and save image as tar file
save_image_offline() {
    local image="$1"
    local image_name=$(echo "$image" | sed 's/[/:]/_/g')
    local tar_file="${OFFLINE_DIR}/${image_name}.tar"
    
    log_info "Processing image: $image"
    
    # Pull image
    log_info "  Pulling image..."
    if ! docker pull "$image"; then
        log_error "  Failed to pull $image"
        return 1
    fi
    
    # Save as tar file
    log_info "  Saving to tar file..."
    if ! docker save "$image" -o "$tar_file"; then
        log_error "  Failed to save $image"
        return 1
    fi
    
    # Compress
    log_info "  Compressing..."
    if ! gzip -f "$tar_file"; then
        log_error "  Failed to compress $tar_file"
        return 1
    fi
    
    log_info "  Successfully saved: ${tar_file}.gz"
    return 0
}

# Load images from tar files (for offline deployment)
load_images_offline() {
    log_info "Loading images from offline directory..."
    
    for tar_gz in "${OFFLINE_DIR}"/*.tar.gz; do
        if [ ! -f "$tar_gz" ]; then
            continue
        fi
        
        log_info "Loading: $tar_gz"
        
        # Decompress
        local tar_file="${tar_gz%.gz}"
        gunzip -c "$tar_gz" > "$tar_file"
        
        # Load image
        docker load -i "$tar_file"
        
        # Cleanup
        rm -f "$tar_file"
        
        log_info "  Loaded successfully"
    done
    
    log_info "All images loaded successfully"
}

# Create README for offline images
create_readme() {
    local readme="${OFFLINE_DIR}/README.md"
    
    cat > "$readme" <<EOF
# Offline Docker Images for Doris GKE Cluster

## Directory Contents

This directory contains Docker images saved as compressed tar files for offline deployment.

## Images List

$(grep -v '^#' "$IMAGES_LIST" | grep -v '^$' | sed 's/^/- /')

## Usage

### On Internet-Connected Machine

1. Run prepare-offline.sh to download and save images:
   \`\`\`bash
   cd doris-gke-cluster
   ./scripts/prepare-offline.sh prepare
   \`\`\`

2. Copy the offline-images directory to target machine

### On Offline Machine

1. Load images into local Docker:
   \`\`\`bash
   cd doris-gke-cluster
   ./scripts/prepare-offline.sh load
   \`\`\`

2. Tag and push images to Nexus:
   \`\`\`bash
   ./scripts/sync-images.sh --offline
   \`\`\`

## File Size

$(du -sh "$OFFLINE_DIR" 2>/dev/null || echo "Directory not created yet")

## Generated

Date: $(date)
Script: prepare-offline.sh
EOF
    
    log_info "Created README: $readme"
}

# ==========================================
# Main Functions
# ==========================================

prepare_offline() {
    log_info "Preparing offline images..."
    log_info "========================================="
    echo ""
    
    create_offline_dir
    echo ""
    
    local total=0
    local success=0
    local failed=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]]; then
            continue
        fi
        
        line=$(echo "$line" | xargs)
        ((total++))
        
        if save_image_offline "$line"; then
            ((success++))
        else
            ((failed++))
        fi
        
        echo ""
    done < "$IMAGES_LIST"
    
    create_readme
    
    log_info "========================================="
    log_info "Preparation Summary:"
    log_info "  Total images: $total"
    log_info "  Successful: $success"
    if [ $failed -gt 0 ]; then
        log_error "  Failed: $failed"
    fi
    log_info "========================================="
    
    log_info "Offline images saved to: $OFFLINE_DIR"
}

load_offline() {
    log_info "Loading offline images..."
    log_info "========================================="
    echo ""
    
    if [ ! -d "$OFFLINE_DIR" ]; then
        log_error "Offline images directory not found: $OFFLINE_DIR"
        exit 1
    fi
    
    load_images_offline
    
    log_info "========================================="
    log_info "All offline images loaded successfully"
}

# ==========================================
# Main Execution
# ==========================================

main() {
    local command="${1:-prepare}"
    
    case "$command" in
        prepare)
            prepare_offline
            ;;
        load)
            load_offline
            ;;
        *)
            echo "Usage: $0 {prepare|load}"
            echo ""
            echo "Commands:"
            echo "  prepare  - Download and save images for offline use"
            echo "  load     - Load images from offline tar files"
            exit 1
            ;;
    esac
}

main "$@"
