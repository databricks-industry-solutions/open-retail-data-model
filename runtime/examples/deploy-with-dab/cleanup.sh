#!/bin/bash

# Databricks Asset Bundle Cleanup Script
# This script removes your deployed DABs project

set -e  # Exit on any error

echo "🧹 Databricks Asset Bundle Cleanup"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    echo "Usage: $0 [-p <profile>] [-t <target>]"
    echo "  -p  Databricks CLI profile the bundle was deployed with (default: the CLI's default profile)"
    echo "  -t  bundle target (default: the bundle's default target)"
}

# Pass the same profile (and target) you deployed with: destroy acts on whatever workspace
# the selected profile points at.
ARGS=()
while getopts ":p:t:h" opt; do
    case $opt in
        p) ARGS+=(--profile "$OPTARG") ;;
        t) ARGS+=(--target "$OPTARG") ;;
        h) usage; exit 0 ;;
        :) print_error "-$OPTARG needs a value"; usage; exit 1 ;;
        *) print_error "unknown option -$OPTARG"; usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))
if [ "$#" -gt 0 ]; then
    print_error "unexpected argument: $1"; usage; exit 1
fi

# Act on this repository's bundle wherever the script is run from, never on another project's
cd "$(dirname "$0")/../../.."
if ! grep -q '^  name: open_retail_data_model$' databricks.yml 2>/dev/null; then
    print_error "$(pwd)/databricks.yml is not the open_retail_data_model bundle"
    exit 1
fi

# Check if databricks CLI is installed
if ! command -v databricks &> /dev/null; then
    print_error "Databricks CLI is not installed or not in PATH"
    exit 1
fi

# Show what will be destroyed
print_status "Getting current deployment summary..."
databricks bundle summary "${ARGS[@]}"

echo ""
print_warning "⚠️  This will permanently delete all deployed resources!"
print_warning "   • Jobs will be deleted"
print_warning "   • Notebooks will be removed from workspace"
print_warning "   • All bundle artifacts will be cleaned up"
echo ""

read -p "Are you sure you want to destroy the bundle? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Destroying bundle..."
    if databricks bundle destroy "${ARGS[@]}"; then
        print_success "Bundle destroyed successfully!"
    else
        print_error "Bundle destruction failed"
        exit 1
    fi
else
    print_status "Cleanup cancelled"
    exit 0
fi

echo ""
print_success "Cleanup completed! 🎉" 