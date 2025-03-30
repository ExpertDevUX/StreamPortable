#!/bin/bash

# =============================================
# Complete Streaming Server Setup Script
# =============================================
# This script:
# 1. Executes ssl_config.sh to set up SSL certificates
# 2. Executes stream_config.sh to configure streaming protocols
# =============================================

# Colors for terminal
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}      Complete Streaming Server Setup Script      ${NC}"
echo -e "${BOLD}======================================================${NC}"
echo
echo -e "This script will run both configuration scripts in sequence:"
echo -e "  1. SSL Certificate Configuration (ssl_config.sh)"
echo -e "  2. Streaming Protocol Configuration (stream_config.sh)"
echo
echo -e "${YELLOW}Note: It's recommended to run these scripts on a clean server.${NC}"
echo

read -p "Do you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Script aborted by user."
    exit 0
fi

# Make the scripts executable
chmod +x ssl_config.sh
chmod +x stream_config.sh

# Run the SSL configuration script
echo
echo -e "${BOLD}Step 1: Running SSL Certificate Configuration Script${NC}"
echo
./ssl_config.sh

# Check if the SSL script completed successfully
if [ $? -ne 0 ]; then
    echo -e "${RED}SSL configuration failed. Please check the logs.${NC}"
    exit 1
fi

echo
echo -e "${BOLD}Step 2: Running Streaming Protocol Configuration Script${NC}"
echo
./stream_config.sh

# Check if the streaming script completed successfully
if [ $? -ne 0 ]; then
    echo -e "${RED}Streaming configuration failed. Please check the logs.${NC}"
    exit 1
fi

echo
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}      Complete setup finished successfully!      ${NC}"
echo -e "${GREEN}======================================================${NC}"
echo
echo -e "Your streaming server is now fully configured with:"
echo -e "  - SSL certificates (with automatic renewal)"
echo -e "  - HLS and DASH streaming protocols"
echo
echo -e "Check the README.md file for more information on using your server."
echo
