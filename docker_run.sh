#!/bin/bash
#
# Enhanced PX4 ROS2 development environment launcher
# Automatically detects OS, GPU, and applies appropriate configuration
# Handles Ubuntu, WSL2, and different CUDA scenarios flawlessly
#
# Author: Abdulrahman S. Al-Batati <asmalbatati@hotmail.com>
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_header() {
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}============================================${NC}"
}

# Function to detect OS with enhanced WSL detection
detect_os() {
    print_status "Detecting operating system..."
    
    # Multiple WSL detection methods
    if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
        echo "wsl"
    elif [[ -f /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease; then
        echo "wsl"
    elif [[ -n "$WSL_DISTRO_NAME" ]] || [[ -n "$WSL_INTEROP" ]]; then
        echo "wsl"
    elif [[ -d /mnt/wslg ]] || [[ -d /mnt/c ]] || [[ -d /mnt/wsl ]]; then
        echo "wsl"
    elif [[ -f /proc/version ]] && grep -qi linux /proc/version; then
        echo "linux"
    else
        echo "unknown"
    fi
}

# Function to detect GPU with enhanced CUDA detection
detect_gpu() {
    print_status "Detecting GPU capabilities..."
    
    # Check for NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            local gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits 2>/dev/null || echo "0")
            local gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "Unknown")
            print_success "NVIDIA GPU detected: $gpu_name (Count: $gpu_count)"
            echo "nvidia"
        else
            print_warning "nvidia-smi found but not working"
            echo "none"
        fi
    elif [[ -d /dev/dri ]] && [[ -n "$(ls -A /dev/dri 2>/dev/null)" ]]; then
        print_status "DRI devices found - GPU acceleration may be available"
        echo "generic"
    else
        print_warning "No GPU detected"
        echo "none"
    fi
}

# Function to check Docker installation and version
check_docker() {
    print_status "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    local docker_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null || echo "unknown")
    print_success "Docker version: $docker_version"
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    # Check Docker version for GPU support
    local server_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0.0.0")
    if dpkg --compare-versions "$server_version" lt "19.03" 2>/dev/null; then
        print_warning "Docker version < 19.03 detected. Consider upgrading for better GPU support."
        return 1
    fi
    
    return 0
}

# Function to setup GPU support with enhanced error handling
setup_gpu_support() {
    local os=$1
    local gpu=$2
    
    print_status "Setting up GPU support for $os with $gpu GPU..."
    
    if [[ "$gpu" == "nvidia" ]]; then
        if [[ "$os" == "wsl" ]]; then
            # WSL2 with NVIDIA
            print_status "Configuring WSL2 NVIDIA GPU support..."
            DOCKER_OPTS="$DOCKER_OPTS --gpus all"
            DOCKER_OPTS="$DOCKER_OPTS -e NVIDIA_VISIBLE_DEVICES=all"
            DOCKER_OPTS="$DOCKER_OPTS -e NVIDIA_DRIVER_CAPABILITIES=all"
            DOCKER_OPTS="$DOCKER_OPTS -e __GLX_VENDOR_LIBRARY_NAME=nvidia"
            DOCKER_OPTS="$DOCKER_OPTS -e MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA"
            
            # WSL-specific GPU permissions
            if [[ -e /dev/dxg ]]; then
                sudo chmod 666 /dev/dxg 2>/dev/null || print_warning "Could not set permissions for /dev/dxg"
            fi
            
            if [[ -d /dev/dri ]]; then
                sudo chmod 666 /dev/dri/* 2>/dev/null || print_warning "Could not set permissions for /dev/dri"
            fi
            
        else
            # Linux with NVIDIA
            print_status "Configuring Linux NVIDIA GPU support..."
            
            # Check for nvidia-container-runtime
            if docker info 2>/dev/null | grep -q nvidia; then
                print_success "NVIDIA Container Runtime detected"
                DOCKER_OPTS="$DOCKER_OPTS --gpus all"
            elif command -v nvidia-docker &> /dev/null; then
                print_warning "Using legacy nvidia-docker"
                DOCKER_OPTS="$DOCKER_OPTS --runtime=nvidia"
            else
                print_warning "NVIDIA Container Runtime not found. GPU support may be limited."
                DOCKER_OPTS="$DOCKER_OPTS --gpus all"
            fi
            
            DOCKER_OPTS="$DOCKER_OPTS -e NVIDIA_VISIBLE_DEVICES=all"
            DOCKER_OPTS="$DOCKER_OPTS -e NVIDIA_DRIVER_CAPABILITIES=all"
            DOCKER_OPTS="$DOCKER_OPTS -e __GLX_VENDOR_LIBRARY_NAME=nvidia"
        fi
        
        print_success "NVIDIA GPU support configured"
        
    elif [[ "$gpu" == "generic" ]]; then
        print_status "Configuring generic GPU support..."
        
        # Add DRI devices for hardware acceleration
        if [[ -d /dev/dri ]]; then
            DOCKER_OPTS="$DOCKER_OPTS --device /dev/dri"
            print_success "DRI devices added for hardware acceleration"
        fi
        
    else
        print_warning "Running in CPU-only mode"
    fi
}

# Function to setup display with enhanced error handling
setup_display() {
    local os=$1
    
    print_status "Setting up display forwarding for $os..."
    
    if [[ "$os" == "wsl" ]]; then
        # WSL2 display setup
        print_status "Configuring WSL2 display forwarding..."
        
        # Basic display environment
        DOCKER_OPTS="$DOCKER_OPTS -e DISPLAY=${DISPLAY:-:0}"
        DOCKER_OPTS="$DOCKER_OPTS -e WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}"
        DOCKER_OPTS="$DOCKER_OPTS -e XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp}"
        DOCKER_OPTS="$DOCKER_OPTS -e PULSE_SERVER=${PULSE_SERVER:-unix:/tmp/pulse-socket}"
        
        # WSL-specific mounts (with existence checks)
        if [[ -d /tmp/.X11-unix ]]; then
            DOCKER_OPTS="$DOCKER_OPTS -v /tmp/.X11-unix:/tmp/.X11-unix:rw"
        fi
        
        if [[ -d /mnt/wslg ]]; then
            DOCKER_OPTS="$DOCKER_OPTS -v /mnt/wslg:/mnt/wslg:ro"
            print_success "WSLg mount added"
        else
            print_warning "WSLg directory not found - GUI applications may not work"
        fi
        
        if [[ -d /usr/lib/wsl ]]; then
            DOCKER_OPTS="$DOCKER_OPTS -v /usr/lib/wsl:/usr/lib/wsl:ro"
            DOCKER_OPTS="$DOCKER_OPTS -e LD_LIBRARY_PATH=/usr/lib/wsl/lib:\${LD_LIBRARY_PATH:-}"
            print_success "WSL library path configured"
        fi
        
        # WSL GPU device access (with error handling)
        if [[ -e /dev/dxg ]]; then
            DOCKER_OPTS="$DOCKER_OPTS --device=/dev/dxg"
            print_success "WSL GPU device /dev/dxg added"
        else
            print_warning "WSL GPU device /dev/dxg not found"
        fi
        
        # DRI devices for WSL
        if [[ -d /dev/dri ]] && [[ -n "$(ls -A /dev/dri 2>/dev/null)" ]]; then
            for device in /dev/dri/*; do
                if [[ -e "$device" ]]; then
                    DOCKER_OPTS="$DOCKER_OPTS --device $device"
                fi
            done
            print_success "DRI devices added for WSL"
        fi
        
    else
        # Linux display setup
        print_status "Configuring Linux display forwarding..."
        
        # Check for X11 display
        if [[ -z "$DISPLAY" ]]; then
            print_warning "DISPLAY environment variable not set"
            export DISPLAY=:0
        fi
        
        # Setup X11 authentication
        XAUTH=/tmp/.docker.xauth
        if [[ ! -f $XAUTH ]]; then
            print_status "Creating X11 authentication file..."
            touch $XAUTH
            chmod a+r $XAUTH
            
            # Get X11 authority list
            if command -v xauth &> /dev/null; then
                xauth_list=$(xauth nlist "$DISPLAY" 2>/dev/null | sed -e 's/^..../ffff/' || true)
                if [[ -n "$xauth_list" ]]; then
                    echo "$xauth_list" | xauth -f $XAUTH nmerge - 2>/dev/null || true
                    print_success "X11 authentication configured"
                else
                    print_warning "Could not get X11 authority list"
                fi
            else
                print_warning "xauth not found - X11 authentication may not work"
            fi
        fi
        
        # Add X11 volumes and environment
        DOCKER_OPTS="$DOCKER_OPTS --volume=/tmp/.X11-unix:/tmp/.X11-unix:rw"
        DOCKER_OPTS="$DOCKER_OPTS --env=DISPLAY=$DISPLAY"
        DOCKER_OPTS="$DOCKER_OPTS --env=QT_X11_NO_MITSHM=1"
        
        if [[ -f $XAUTH ]]; then
            DOCKER_OPTS="$DOCKER_OPTS --volume=$XAUTH:$XAUTH"
            DOCKER_OPTS="$DOCKER_OPTS --env=XAUTHORITY=$XAUTH"
        fi
        
        # Allow X11 connections
        if command -v xhost &> /dev/null; then
            xhost +local:docker 2>/dev/null || print_warning "Could not configure xhost"
        fi
        
        # Add DRI devices for GPU access
        if [[ -d /dev/dri ]]; then
            DOCKER_OPTS="$DOCKER_OPTS --device /dev/dri"
            print_success "DRI devices added for hardware acceleration"
        else
            print_warning "DRI devices not found - hardware acceleration may not work"
        fi
    fi
    
    print_success "Display forwarding configured"
}

# Function to setup workspace directory
setup_workspace() {
    local workspace_dir=$1
    
    print_status "Setting up workspace directory: $workspace_dir"
    
    if [[ ! -d "$workspace_dir" ]]; then
        if mkdir -p "$workspace_dir"; then
            print_success "Created workspace directory: $workspace_dir"
        else
            print_error "Failed to create workspace directory: $workspace_dir"
            exit 1
        fi
    else
        print_success "Workspace directory exists: $workspace_dir"
    fi
    
    # Set proper permissions
    if [[ -w "$workspace_dir" ]]; then
        print_success "Workspace directory is writable"
    else
        print_warning "Workspace directory is not writable - attempting to fix permissions"
        chmod 755 "$workspace_dir" 2>/dev/null || {
            print_error "Could not set permissions for workspace directory"
            exit 1
        }
    fi
}

# Function to check if container exists and is running
check_container_status() {
    local container_name=$1
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            echo "running"
        else
            echo "stopped"
        fi
    else
        echo "not_exists"
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [CONTAINER_NAME]"
    echo ""
    echo "Description:"
    echo "  Launch PX4 ROS2 development environment with automatic OS and GPU detection"
    echo ""
    echo "Arguments:"
    echo "  CONTAINER_NAME          Custom container name (default: px4_ros2_jazzy)"
    echo ""
    echo "Options:"
    echo "  --help, -h              Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  GIT_USER                Git username for authenticated repository access"
    echo "  GIT_TOKEN               Git token for authenticated repository access"
    echo ""
    echo "Examples:"
    echo "  $0                      # Start with default container name"
    echo "  $0 my_px4_dev          # Start with custom container name"
    echo "  GIT_USER=user GIT_TOKEN=token $0    # Start with git credentials"
    echo ""
    echo "Features:"
    echo "  - Automatic OS detection (Ubuntu/WSL2)"
    echo "  - Automatic GPU detection (NVIDIA/Generic/CPU-only)"
    echo "  - Cross-platform display forwarding"
    echo "  - Persistent workspace volume"
    echo "  - Container restart/attach functionality"
}

# Main script
main() {
    # Check for help option first
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        show_usage
        exit 0
    fi
    
    print_header "PX4 ROS2 Jazzy Docker Environment"
    
    # Check Docker installation
    check_docker
    
    # Detect environment
    OS=$(detect_os)
    GPU=$(detect_gpu)
    
    print_status "Detected OS: $OS"
    print_status "Detected GPU: $GPU"
    
    # Configuration
    DOCKER_REPO="px4-dev-simulation-ubuntu24"
    CONTAINER_NAME="px4_ros2_jazzy"
    WORKSPACE_DIR=~/px4_ros2_jazzy_shared_volume
    
    # Allow custom container name
    if [[ -n "$1" ]]; then
        CONTAINER_NAME=$1
        WORKSPACE_DIR=~/${CONTAINER_NAME}_shared_volume
    fi
    
    print_status "Container name: $CONTAINER_NAME"
    print_status "Workspace directory: $WORKSPACE_DIR"
    
    # Setup workspace directory
    setup_workspace "$WORKSPACE_DIR"
    
    # Initialize Docker options
    DOCKER_OPTS=""
    
    # Setup GPU support
    setup_gpu_support "$OS" "$GPU"
    
    # Setup display
    setup_display "$OS"
    
    # Common options
    DOCKER_OPTS="$DOCKER_OPTS --privileged"
    DOCKER_OPTS="$DOCKER_OPTS --network host"
    DOCKER_OPTS="$DOCKER_OPTS --restart unless-stopped"
    DOCKER_OPTS="$DOCKER_OPTS -e LOCAL_USER_ID=$(id -u)"
    DOCKER_OPTS="$DOCKER_OPTS -e LOCAL_GROUP_ID=$(id -g)"
    DOCKER_OPTS="$DOCKER_OPTS -e CONTAINER_NAME=$CONTAINER_NAME"
    DOCKER_OPTS="$DOCKER_OPTS -e FASTRTPS_DEFAULT_PROFILES_FILE=/usr/local/share/middleware_profiles/rtps_udp_profile.xml"
    DOCKER_OPTS="$DOCKER_OPTS -e RMW_IMPLEMENTATION=rmw_zenoh_cpp"
    DOCKER_OPTS="$DOCKER_OPTS -e GZ_VERSION=harmonic"
    DOCKER_OPTS="$DOCKER_OPTS --volume=$WORKSPACE_DIR:/home/user/shared_volume:rw"
    DOCKER_OPTS="$DOCKER_OPTS --volume=/etc/localtime:/etc/localtime:ro"
    DOCKER_OPTS="$DOCKER_OPTS --workdir /home/user/shared_volume"
    
    # Device access (with error handling)
    if [[ -d /dev/input ]]; then
        DOCKER_OPTS="$DOCKER_OPTS --volume=/dev/input:/dev/input:ro"
    fi
    
    if [[ -d /dev/bus/usb ]]; then
        DOCKER_OPTS="$DOCKER_OPTS --volume=/dev/bus/usb:/dev/bus/usb:ro"
    fi
    
    # PX4-specific ports
    DOCKER_OPTS="$DOCKER_OPTS -p 14550:14550/udp"  # MAVLink
    DOCKER_OPTS="$DOCKER_OPTS -p 14556:14556/udp"  # MAVLink secondary
    DOCKER_OPTS="$DOCKER_OPTS -p 14557:14557/udp"  # MAVROS
    DOCKER_OPTS="$DOCKER_OPTS -p 14540:14540/udp"  # MAVROS FCU
    DOCKER_OPTS="$DOCKER_OPTS -p 8888:8888/udp"    # XRCE-DDS
    DOCKER_OPTS="$DOCKER_OPTS -p 5760:5760/tcp"    # QGroundControl
    
    # Setup command
    CMD="export DEV_DIR=/home/user/shared_volume && \
        export PX4_DIR=\$DEV_DIR/PX4-Autopilot && \
        export ROS2_WS=\$DEV_DIR/ros2_ws && \
        export OSQP_SRC=\$DEV_DIR && \
        source /home/user/.bashrc && \
        if [ -f \"/home/user/shared_volume/ros2_ws/install/setup.bash\" ]; then \
            source /home/user/shared_volume/ros2_ws/install/setup.bash; \
        fi && \
        echo 'PX4 ROS2 Development Environment Ready!' && \
        echo 'Workspace: /home/user/shared_volume' && \
        echo 'To run install script: cd /home/user/shared_volume/ros2_ws/src/uav_gz_sim && ./install.sh' && \
        /bin/bash"
    
    # Add environment variables if available
    if [[ -n "$GIT_TOKEN" ]] && [[ -n "$GIT_USER" ]]; then
        DOCKER_OPTS="$DOCKER_OPTS -e GIT_USER=$GIT_USER -e GIT_TOKEN=$GIT_TOKEN"
        print_success "Git credentials configured"
    fi
    
    # Check container status
    CONTAINER_STATUS=$(check_container_status "$CONTAINER_NAME")
    
    case $CONTAINER_STATUS in
        "running")
            print_success "Container is already running. Attaching to it..."
            docker exec --user user -it "$CONTAINER_NAME" env TERM=xterm-256color bash -c "$CMD"
            ;;
        "stopped")
            print_status "Restarting existing container..."
            docker start "$CONTAINER_NAME"
            docker exec --user user -it "$CONTAINER_NAME" env TERM=xterm-256color bash -c "$CMD"
            ;;
        "not_exists")
            print_status "Creating and running new container..."
            print_status "Docker command: docker run -it --name $CONTAINER_NAME $DOCKER_OPTS $DOCKER_REPO"
            
            # shellcheck disable=SC2086
            docker run -it \
                --name "$CONTAINER_NAME" \
                $DOCKER_OPTS \
                "$DOCKER_REPO" \
                bash -c "$CMD"
            ;;
    esac
    
    print_success "Docker environment session completed"
}

# Run main function with all arguments
main "$@" 