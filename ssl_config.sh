#!/bin/bash

# ============================================================
# SSL Configuration Script
# ============================================================
# This script:
# 1. Installs SSL certificates via Certbot
# 2. Configures automatic renewal
# ============================================================

# Text formatting
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/ssl_config.log"
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

# Function to log messages
log() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Function to log errors
log_error() {
    log "$1" "ERROR"
    echo -e "${RED}ERROR: $1${NC}"
}

# Function to log success
log_success() {
    log "$1" "SUCCESS"
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

# Function to log info with color
log_info() {
    log "$1" "INFO"
    echo -e "${BLUE}INFO: $1${NC}"
}

# Function to log warnings
log_warning() {
    log "$1" "WARNING"
    echo -e "${YELLOW}WARNING: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if the script is run as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Function to detect the Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        # freedesktop.org and systemd
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        # linuxbase.org
        OS=$(lsb_release -si)
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        # For some versions of Debian/Ubuntu without lsb_release command
        . /etc/lsb-release
        OS=$DISTRIB_ID
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        # Older Debian/Ubuntu/etc.
        OS=Debian
        VER=$(cat /etc/debian_version)
    else
        # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    
    log_info "Detected OS: $OS $VER"
}

# Function to install required packages
install_dependencies() {
    log_info "Installing dependencies..."
    
    case "$OS" in
        *Ubuntu*|*Debian*)
            apt-get update
            apt-get install -y nginx certbot python3-certbot-nginx
            ;;
        *CentOS*|*RHEL*|*Fedora*)
            yum -y install epel-release
            yum -y install nginx certbot python3-certbot-nginx
            ;;
        *SUSE*)
            zypper install -y nginx certbot python-certbot-nginx
            ;;
        *)
            log_error "Unsupported Linux distribution. Please install Nginx and Certbot manually."
            exit 1
            ;;
    esac
    
    if command_exists nginx && command_exists certbot; then
        log_success "Dependencies installed successfully."
    else
        log_error "Failed to install dependencies."
        exit 1
    fi
}

# Function to install SSL certificate
install_ssl() {
    log_info "Installing SSL certificate..."
    
    # Ask for domain name
    echo -e "${BOLD}Enter your domain name (e.g., stream.example.com):${NC}"
    read domain_name
    
    if [ -z "$domain_name" ]; then
        log_error "Domain name cannot be empty."
        exit 1
    fi
    
    # Check if the domain resolves to this server's IP
    server_ip=$(curl -s ifconfig.me)
    domain_ip=$(dig +short "$domain_name")
    
    if [ -z "$domain_ip" ]; then
        log_warning "Could not resolve IP for $domain_name. Make sure DNS is correctly configured."
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "SSL installation aborted."
            exit 1
        fi
    elif [ "$domain_ip" != "$server_ip" ]; then
        log_warning "Domain $domain_name resolves to $domain_ip but this server's IP is $server_ip."
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "SSL installation aborted."
            exit 1
        fi
    fi
    
    # Install SSL certificate
    log_info "Running Certbot for $domain_name..."
    certbot --nginx -d "$domain_name" --non-interactive --agree-tos --email webmaster@"$domain_name" --redirect
    
    if [ $? -eq 0 ]; then
        log_success "SSL certificate installed successfully for $domain_name."
    else
        log_error "Failed to install SSL certificate."
        exit 1
    fi
    
    # Save domain for later use (will be used by the streaming config script)
    echo "$domain_name" > /tmp/stream_domain.txt
}

# Function to test the configuration and restart Nginx
test_and_restart() {
    log_info "Testing NGINX configuration..."
    
    nginx -t
    
    if [ $? -eq 0 ]; then
        log_info "NGINX configuration is valid. Restarting NGINX..."
        
        # Restart nginx service based on the init system
        if command_exists systemctl; then
            systemctl restart nginx
        elif command_exists service; then
            service nginx restart
        else
            /etc/init.d/nginx restart
        fi
        
        if [ $? -eq 0 ]; then
            log_success "NGINX restarted successfully."
        else
            log_error "Failed to restart NGINX."
            exit 1
        fi
    else
        log_error "NGINX configuration is invalid. Please check the error above."
        exit 1
    fi
}

# Function to configure automatic SSL renewal
configure_ssl_renewal() {
    log_info "Setting up automatic SSL renewal..."
    
    # Creating renewal script
    cat > /etc/cron.weekly/certbot-renew << 'EOF'
#!/bin/bash
certbot renew --quiet --no-self-upgrade

# Restart Nginx after renewal
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart nginx
elif command -v service >/dev/null 2>&1; then
    service nginx restart
else
    /etc/init.d/nginx restart
fi
EOF

    chmod +x /etc/cron.weekly/certbot-renew
    
    log_success "Automatic SSL renewal configured."
}

# Main function
main() {
    clear
    echo -e "${BOLD}======================================================${NC}"
    echo -e "${BOLD}      SSL Certificate Configuration Script      ${NC}"
    echo -e "${BOLD}======================================================${NC}"
    echo
    echo -e "This script will:"
    echo -e "  1. Install SSL certificates via Certbot"
    echo -e "  2. Configure automatic SSL renewal"
    echo
    echo -e "${YELLOW}Note: This script assumes you have Nginx installed.${NC}"
    echo
    
    read -p "Do you want to continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Script aborted by user."
        exit 0
    fi
    
    # Initialize log file
    echo "=== SSL Configuration Log - $(date) ===" > "$LOG_FILE"
    
    # Execute functions
    check_root
    detect_distro
    install_dependencies
    install_ssl
    test_and_restart
    configure_ssl_renewal
    
    echo
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}      SSL Configuration completed successfully!      ${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo
    echo -e "Your server now has:"
    echo -e "  - SSL certificates installed"
    echo -e "  - Automatic certificate renewal configured"
    echo
    echo -e "Domain name: $(cat /tmp/stream_domain.txt)"
    echo -e "SSL certificate location: /etc/letsencrypt/live/$(cat /tmp/stream_domain.txt)"
    echo
    echo -e "To configure streaming protocols, run the stream_config.sh script."
    echo
}

# Run the main function
main
