#!/bin/bash

# ============================================================
# Streaming Protocol Configuration Script
# ============================================================
# This script:
# 1. Configures HLS (HTTP Live Streaming) protocol
# 2. Configures DASH (Dynamic Adaptive Streaming over HTTP) protocol
# 3. Integrates with existing RTMP server
# ============================================================

# Text formatting
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/stream_config.log"
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
            apt-get install -y nginx ffmpeg
            ;;
        *CentOS*|*RHEL*|*Fedora*)
            yum -y install epel-release
            yum -y install nginx ffmpeg
            ;;
        *SUSE*)
            zypper install -y nginx ffmpeg
            ;;
        *)
            log_error "Unsupported Linux distribution. Please install Nginx and FFmpeg manually."
            exit 1
            ;;
    esac
    
    if command_exists nginx && command_exists ffmpeg; then
        log_success "Dependencies installed successfully."
    else
        log_error "Failed to install dependencies."
        exit 1
    fi
}

# Function to verify Nginx RTMP module is installed
verify_rtmp_module() {
    log_info "Verifying NGINX RTMP module..."
    
    if nginx -V 2>&1 | grep -q "nginx-rtmp-module"; then
        log_success "NGINX RTMP module is installed."
    else
        log_warning "NGINX RTMP module may not be installed. The script will attempt to configure RTMP, but you may need to rebuild Nginx with the RTMP module."
        
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Script aborted by user."
            exit 1
        fi
    fi
}

# This function has been moved to ssl_config.sh

# Function to configure HLS
configure_hls() {
    log_info "Configuring HLS (HTTP Live Streaming)..."
    
    # Create directories for HLS
    mkdir -p /var/www/html/hls
    chown -R www-data:www-data /var/www/html/hls
    chmod -R 755 /var/www/html/hls
    
    # Add HLS configuration to RTMP section
    if grep -q "rtmp {" "$NGINX_CONF"; then
        if ! grep -q "hls_path" "$NGINX_CONF"; then
            # Extract the rtmp block to modify it
            rtmp_block=$(awk '/rtmp {/,/}/' "$NGINX_CONF")
            
            # Check if there's an existing application block
            if echo "$rtmp_block" | grep -q "application live {"; then
                # Modify the existing application block
                sed -i '/application live {/,/}/{s|application live {|application live {\n        # HLS Configuration\n        hls on;\n        hls_path /var/www/html/hls;\n        hls_fragment 3;\n        hls_playlist_length 60;\n|g}' "$NGINX_CONF"
            else
                # Add a new application block inside the rtmp block
                sed -i '/rtmp {/,/}/{s|rtmp {|rtmp {\n    server {\n        listen 1935;\n        \n        application live {\n            live on;\n            record off;\n            \n            # HLS Configuration\n            hls on;\n            hls_path /var/www/html/hls;\n            hls_fragment 3;\n            hls_playlist_length 60;\n        }\n    }|g}' "$NGINX_CONF"
            fi
        else
            log_warning "HLS configuration already exists in NGINX config."
        fi
    else
        log_error "RTMP section not found in NGINX config. Please make sure RTMP is properly configured."
        exit 1
    fi
    
    log_success "HLS configuration added to NGINX RTMP section."
}

# Function to configure DASH
configure_dash() {
    log_info "Configuring DASH (Dynamic Adaptive Streaming over HTTP)..."
    
    # Create directories for DASH
    mkdir -p /var/www/html/dash
    chown -R www-data:www-data /var/www/html/dash
    chmod -R 755 /var/www/html/dash
    
    # Add DASH configuration to RTMP section
    if grep -q "rtmp {" "$NGINX_CONF"; then
        if ! grep -q "dash_path" "$NGINX_CONF"; then
            # Add DASH configuration to the existing application block
            sed -i '/application live {/,/}/{s|application live {|application live {\n        # DASH Configuration\n        dash on;\n        dash_path /var/www/html/dash;\n        dash_fragment 3;\n        dash_playlist_length 60;\n|g}' "$NGINX_CONF"
        else
            log_warning "DASH configuration already exists in NGINX config."
        fi
    else
        log_error "RTMP section not found in NGINX config. Please make sure RTMP is properly configured."
        exit 1
    fi
    
    log_success "DASH configuration added to NGINX RTMP section."
}

# Function to create HTTP server blocks for HLS and DASH access
configure_http_server() {
    log_info "Configuring HTTP server for streaming access..."
    
    domain_name=$(cat /tmp/stream_domain.txt)
    
    # Create a new server block configuration file
    cat > "$NGINX_SITES_AVAILABLE/streaming" << EOF
server {
    listen 80;
    server_name $domain_name;
    
    # Redirect all HTTP requests to HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name $domain_name;
    
    # SSL configuration handled by Certbot
    
    # HLS
    location /hls {
        # Serve HLS fragments
        types {
            application/vnd.apple.mpegurl m3u8;
            video/mp2t ts;
        }
        
        root /var/www/html;
        add_header Cache-Control no-cache;
        add_header Access-Control-Allow-Origin *;
    }
    
    # DASH
    location /dash {
        # Serve DASH fragments
        types {
            application/dash+xml mpd;
            video/mp4 mp4;
        }
        
        root /var/www/html;
        add_header Cache-Control no-cache;
        add_header Access-Control-Allow-Origin *;
    }
    
    # RTMP stat
    location /stat {
        rtmp_stat all;
        rtmp_stat_stylesheet stat.xsl;
    }
    
    location /stat.xsl {
        root /var/www/html;
    }
    
    # Simple status page
    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF
    
    # Create a simple status page
    cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Streaming Server</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        h1 {
            color: #333;
        }
        .info {
            background: #f4f4f4;
            padding: 15px;
            border-radius: 5px;
        }
        code {
            background: #e4e4e4;
            padding: 2px 5px;
            border-radius: 3px;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <h1>Streaming Server Status</h1>
    <div class="info">
        <h2>Stream URLs</h2>
        <p>RTMP Stream URL: <code>rtmp://$domain_name/live/stream</code></p>
        <p>HLS Stream URL: <code>https://$domain_name/hls/stream.m3u8</code></p>
        <p>DASH Stream URL: <code>https://$domain_name/dash/stream.mpd</code></p>
        <h2>Server Status</h2>
        <p>RTMP Statistics: <a href="/stat">View Stats</a></p>
    </div>
</body>
</html>
EOF
    
    # Enable the site
    ln -sf "$NGINX_SITES_AVAILABLE/streaming" "$NGINX_SITES_ENABLED/streaming"
    
    log_success "HTTP server configuration created for streaming access."
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

# This function has been moved to ssl_config.sh

# Function to verify the setup
verify_setup() {
    log_info "Verifying setup..."
    
    domain_name=$(cat /tmp/stream_domain.txt)
    
    # Check if Nginx is running
    if pgrep nginx > /dev/null; then
        log_success "NGINX is running."
    else
        log_error "NGINX is not running. Please check NGINX logs for errors."
        exit 1
    fi
    
    # Verifying HLS directory exists and is writable
    if [ -d "/var/www/html/hls" ] && [ -w "/var/www/html/hls" ]; then
        log_success "HLS directory exists and is writable."
    else
        log_error "HLS directory does not exist or is not writable."
        exit 1
    fi
    
    # Verifying DASH directory exists and is writable
    if [ -d "/var/www/html/dash" ] && [ -w "/var/www/html/dash" ]; then
        log_success "DASH directory exists and is writable."
    else
        log_error "DASH directory does not exist or is not writable."
        exit 1
    fi
    
    # Check SSL certificate
    if curl -s -I "https://$domain_name" | grep -q "200 OK"; then
        log_success "SSL certificate is working correctly."
    else
        log_warning "Could not verify SSL certificate. Make sure DNS is correctly configured."
    fi
    
    log_info "Setup verification completed."
}

# Main function
main() {
    clear
    echo -e "${BOLD}======================================================${NC}"
    echo -e "${BOLD}      Streaming Protocol Configuration Script      ${NC}"
    echo -e "${BOLD}======================================================${NC}"
    echo
    echo -e "This script will:"
    echo -e "  1. Configure HLS (HTTP Live Streaming) protocol"
    echo -e "  2. Configure DASH (Dynamic Adaptive Streaming over HTTP) protocol"
    echo -e "  3. Integrate with your existing RTMP server"
    echo
    echo -e "${YELLOW}Note: This script assumes you have a working RTMP server with Nginx and SSL certificates installed.${NC}"
    echo -e "${YELLOW}Run ssl_config.sh first if you haven't installed SSL certificates yet.${NC}"
    echo
    
    read -p "Do you want to continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Script aborted by user."
        exit 0
    fi
    
    # Check if domain file exists (created by ssl_config.sh)
    if [ ! -f "/tmp/stream_domain.txt" ]; then
        echo -e "${BOLD}Enter your domain name (e.g., stream.example.com):${NC}"
        read domain_name
        
        if [ -z "$domain_name" ]; then
            log_error "Domain name cannot be empty."
            exit 1
        fi
        
        # Save domain for later use
        echo "$domain_name" > /tmp/stream_domain.txt
        log_info "Domain name saved: $domain_name"
    else
        domain_name=$(cat /tmp/stream_domain.txt)
        log_info "Using domain name from previous SSL configuration: $domain_name"
    fi
    
    # Initialize log file
    echo "=== Stream Configuration Log - $(date) ===" > "$LOG_FILE"
    
    # Execute functions
    check_root
    detect_distro
    install_dependencies
    verify_rtmp_module
    configure_hls
    configure_dash
    configure_http_server
    test_and_restart
    verify_setup
    # Note: SSL renewal is handled by ssl_config.sh
    
    echo
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}      Streaming Configuration completed successfully!      ${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo
    echo -e "Your streaming server is now configured with:"
    echo -e "  - HLS streaming protocol"
    echo -e "  - DASH streaming protocol"
    echo
    
    domain_name=$(cat /tmp/stream_domain.txt)
    echo -e "Stream URLs:"
    echo -e "  - RTMP: rtmp://$domain_name/live/stream"
    echo -e "  - HLS:  https://$domain_name/hls/stream.m3u8"
    echo -e "  - DASH: https://$domain_name/dash/stream.mpd"
    echo
    echo -e "To stream to this server, use OBS or similar software with these settings:"
    echo -e "  - Service: Custom"
    echo -e "  - Server: rtmp://$domain_name/live"
    echo -e "  - Stream Key: stream"
    echo
    echo -e "Visit https://$domain_name to view streaming status."
    echo -e "Log file is available at: $LOG_FILE"
    echo
    
    # Clean up temporary files
    rm -f /tmp/stream_domain.txt
}

# Run the script
main
