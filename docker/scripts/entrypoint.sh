#!/bin/bash

# Enhanced entrypoint script for PX4 ROS2 development environment
# Handles permissions across Ubuntu, WSL2, and different user scenarios

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[ENTRYPOINT]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[ENTRYPOINT]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[ENTRYPOINT]${NC} $1"
}

print_error() {
    echo -e "${RED}[ENTRYPOINT]${NC} $1"
}

# Function to detect if running in WSL
detect_wsl() {
    if [[ -f /proc/version ]] && grep -q Microsoft /proc/version; then
        echo "true"
    elif [[ -n "$WSL_DISTRO_NAME" ]] || [[ -n "$WSL_INTEROP" ]]; then
        echo "true"
    elif [[ -d /mnt/wslg ]] || [[ -d /mnt/c ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to setup device permissions
setup_device_permissions() {
    local is_wsl=$1
    
    print_status "Setting up device permissions..."
    
    # GPU device permissions
    if [[ -d "/dev/dri" ]]; then
        chmod 666 /dev/dri/* 2>/dev/null || {
            print_warning "Could not set permissions for /dev/dri devices"
        }
    fi
    
    # WSL-specific GPU device
    if [[ -e "/dev/dxg" ]]; then
        chmod 666 /dev/dxg 2>/dev/null || {
            print_warning "Could not set permissions for /dev/dxg"
        }
    fi
    
    # USB and input devices
    if [[ -d "/dev/input" ]]; then
        chmod 666 /dev/input/* 2>/dev/null || true
    fi
    
    if [[ -d "/dev/bus/usb" ]]; then
        find /dev/bus/usb -type c -exec chmod 666 {} \; 2>/dev/null || true
    fi
    
    # Serial devices for PX4
    if [[ -d "/dev/serial" ]]; then
        chmod 666 /dev/serial/by-id/* 2>/dev/null || true
    fi
    
    # TTY devices
    chmod 666 /dev/tty* 2>/dev/null || true
    
    print_success "Device permissions configured"
}

# Function to setup user and groups
setup_user_groups() {
    local user_id=$1
    local group_id=$2
    
    print_status "Setting up user and groups (UID: $user_id, GID: $group_id)..."
    
    # Handle user creation/modification
    if id user >/dev/null 2>&1; then
        # User exists, check if UID needs to be changed
        current_uid=$(id -u user)
        if [[ "$current_uid" != "$user_id" ]]; then
            print_status "Changing user UID from $current_uid to $user_id"
            usermod -u "$user_id" user >/dev/null 2>&1 || {
                print_warning "Could not change user UID, continuing with existing UID"
            }
        fi
    else
        # Create user
        print_status "Creating user with UID $user_id"
        useradd --shell /bin/bash -u "$user_id" -c "PX4 Development User" -m user || {
            print_error "Failed to create user"
            exit 1
        }
        echo "user:user" | chpasswd
    fi
    
    # Handle group creation/modification
    if getent group user >/dev/null 2>&1; then
        # Group exists, check if GID needs to be changed
        current_gid=$(getent group user | cut -d: -f3)
        if [[ "$current_gid" != "$group_id" ]]; then
            print_status "Changing group GID from $current_gid to $group_id"
            groupmod -g "$group_id" user >/dev/null 2>&1 || {
                print_warning "Could not change group GID, continuing with existing GID"
            }
        fi
    else
        # Create group
        print_status "Creating group with GID $group_id"
        groupadd -g "$group_id" user || {
            print_warning "Could not create group with GID $group_id, using default"
        }
    fi
    
    # Add user to necessary groups for device access
    print_status "Adding user to necessary groups..."
    local groups_to_add=("dialout" "plugdev" "video" "audio" "render" "input" "tty")
    
    for group in "${groups_to_add[@]}"; do
        if getent group "$group" >/dev/null 2>&1; then
            usermod -a -G "$group" user >/dev/null 2>&1 || {
                print_warning "Could not add user to group $group"
            }
        fi
    done
    
    # Add user to sudo group and configure sudoers
    usermod -a -G sudo user >/dev/null 2>&1 || {
        print_warning "Could not add user to sudo group"
    }
    
    # Configure passwordless sudo for user
    echo "user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/user || {
        print_warning "Could not configure passwordless sudo"
    }
    
    print_success "User and groups configured"
}

# Function to setup directories and permissions
setup_directories() {
    local user_id=$1
    local group_id=$2
    
    print_status "Setting up directories and permissions..."
    
    # Create necessary directories
    mkdir -p /home/user/shared_volume
    mkdir -p /home/user/.config
    mkdir -p /home/user/.cache
    mkdir -p /home/user/.local/share
    
    # Set ownership of user home directory
    chown -R "$user_id:$group_id" /home/user 2>/dev/null || {
        print_warning "Could not set ownership of /home/user"
    }
    
    # Set proper permissions
    chmod 755 /home/user
    chmod 755 /home/user/shared_volume
    
    # Create workspace directories if they don't exist
    mkdir -p /home/user/shared_volume/ros2_ws/src
    mkdir -p /home/user/shared_volume/PX4-Autopilot
    
    # Set ownership of workspace
    chown -R "$user_id:$group_id" /home/user/shared_volume 2>/dev/null || {
        print_warning "Could not set ownership of shared volume"
    }
    
    print_success "Directories and permissions configured"
}

# Function to setup environment
setup_environment() {
    print_status "Setting up environment variables..."
    
    # Export development environment variables
    export DEV_DIR=/home/user/shared_volume
    export PX4_DIR=$DEV_DIR/PX4-Autopilot
    export ROS2_WS=$DEV_DIR/ros2_ws
    export OSQP_SRC=$DEV_DIR
    
    # Export Git credentials if provided
    if [[ -n "$GIT_TOKEN" ]] && [[ -n "$GIT_USER" ]]; then
        export GIT_USER="$GIT_USER"
        export GIT_TOKEN="$GIT_TOKEN"
        print_success "Git credentials configured"
    fi
    
    # Export sudo password if provided
    if [[ -n "$SUDO_PASSWORD" ]]; then
        export SUDO_PASSWORD="$SUDO_PASSWORD"
    fi
    
    # Setup ROS environment
    if [[ -n "${ROS_DISTRO}" ]]; then
        export ROS_DISTRO="$ROS_DISTRO"
        if [[ -f "/opt/ros/$ROS_DISTRO/setup.bash" ]]; then
            # shellcheck source=/dev/null
            source "/opt/ros/$ROS_DISTRO/setup.bash"
            print_success "ROS $ROS_DISTRO environment sourced"
        fi
    fi
    
    # Setup Gazebo environment
    if [[ -n "${GZ_VERSION}" ]]; then
        export GZ_VERSION="$GZ_VERSION"
    fi
    
    print_success "Environment variables configured"
}

# Function to start virtual X server if needed
setup_display() {
    local is_wsl=$1
    
    # Start virtual X server in the background if needed
    if [[ -x "$(command -v Xvfb)" && "$DISPLAY" == ":99" ]]; then
        print_status "Starting virtual X server (Xvfb)"
        Xvfb :99 -screen 0 1600x1200x24+32 &
        export DISPLAY=:99
        print_success "Virtual X server started"
    fi
    
    # WSL-specific display setup
    if [[ "$is_wsl" == "true" ]]; then
        print_status "Configuring WSL display forwarding..."
        
        # Set WSL-specific environment variables
        export MESA_D3D12_DEFAULT_ADAPTER_NAME=${MESA_D3D12_DEFAULT_ADAPTER_NAME:-NVIDIA}
        export LIBGL_ALWAYS_SOFTWARE=${LIBGL_ALWAYS_SOFTWARE:-0}
        
        # Configure library paths for WSL
        if [[ -d "/usr/lib/wsl/lib" ]]; then
            export LD_LIBRARY_PATH="/usr/lib/wsl/lib:${LD_LIBRARY_PATH:-}"
        fi
        
        print_success "WSL display configuration completed"
    fi
}

# Main entrypoint logic
main() {
    print_status "Starting PX4 ROS2 development environment..."
    
    # Detect environment
    IS_WSL=$(detect_wsl)
    print_status "Environment: $([ "$IS_WSL" == "true" ] && echo "WSL2" || echo "Linux")"
    
    # Setup device permissions early
    setup_device_permissions "$IS_WSL"
    
    # Setup display
    setup_display "$IS_WSL"
    
    # Setup environment variables
    setup_environment
    
    # Handle user ID and group ID
    if [[ -n "${LOCAL_USER_ID}" ]]; then
        USER_ID="${LOCAL_USER_ID}"
        GROUP_ID="${LOCAL_GROUP_ID:-${LOCAL_USER_ID}}"
        
        print_status "Using custom user ID: $USER_ID, group ID: $GROUP_ID"
        
        # Setup user and groups
        setup_user_groups "$USER_ID" "$GROUP_ID"
        
        # Setup directories and permissions
        setup_directories "$USER_ID" "$GROUP_ID"
        
        # Create a startup script for the user
        cat > /tmp/user_startup.sh << 'EOF'
#!/bin/bash
# Source ROS environment
if [ -f "/opt/ros/jazzy/setup.bash" ]; then
    source /opt/ros/jazzy/setup.bash
fi

# Source workspace if it exists
if [ -f "/home/user/shared_volume/ros2_ws/install/setup.bash" ]; then
    source /home/user/shared_volume/ros2_ws/install/setup.bash
fi

# Source user bashrc
if [ -f "/home/user/.bashrc" ]; then
    source /home/user/.bashrc
fi

# Execute the command
exec "$@"
EOF
        chmod +x /tmp/user_startup.sh
        chown "$USER_ID:$GROUP_ID" /tmp/user_startup.sh
        
        print_success "Container initialization completed"
        print_status "Switching to user context..."
        
        # Switch to user and execute command
        exec gosu user /tmp/user_startup.sh "$@"
    else
        print_status "Running as root user"
        exec "$@"
    fi
}

# Run main function
main "$@"