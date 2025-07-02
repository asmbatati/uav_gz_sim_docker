#!/bin/bash
#
# Unified PX4 ROS2 development environment
# Automatically detects OS, GPU, and applies appropriate configuration
#
# Author: Abdulrahman S. Al-Batati <asmalbatati@hotmail.com>
#

set -e

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

# Function to detect OS
detect_os() {
    # Debug output
    echo "Debug: Checking WSL indicators..." >&2
    
    # Check multiple WSL indicators
    if [[ -f /proc/version ]] && grep -q Microsoft /proc/version; then
        echo "Debug: Found Microsoft in /proc/version" >&2
        echo "wsl"
    elif [[ -f /proc/sys/kernel/osrelease ]] && grep -q Microsoft /proc/sys/kernel/osrelease; then
        echo "Debug: Found Microsoft in /proc/sys/kernel/osrelease" >&2
        echo "wsl"
    elif [[ -n "$WSL_DISTRO_NAME" ]] || [[ -n "$WSL_INTEROP" ]]; then
        echo "Debug: Found WSL environment variables" >&2
        echo "wsl"
    elif [[ -d /mnt/wslg ]] || [[ -d /mnt/c ]]; then
        echo "Debug: Found WSL mount points" >&2
        echo "wsl"
    else
        echo "Debug: No WSL indicators found, assuming Linux" >&2
        echo "linux"
    fi
}

# Function to detect GPU
detect_gpu() {
    if command -v nvidia-smi &> /dev/null; then
        if nvidia-smi &> /dev/null; then
            echo "nvidia"
        else
            echo "none"
        fi
    else
        echo "none"
    fi
}

# Function to detect Docker version and GPU support
setup_gpu_support() {
    local os=$1
    local gpu=$2
    
    if [[ "$gpu" == "nvidia" ]]; then
        # Get Docker version
        DOCKER_VER=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0.0.0")
        
        if [[ "$os" == "wsl" ]]; then
            # WSL2 with NVIDIA
            print_status "WSL2 detected with NVIDIA GPU"
            DOCKER_OPTS="$DOCKER_OPTS --gpus all"
            DOCKER_OPTS="$DOCKER_OPTS -e NVIDIA_DRIVER_CAPABILITIES=all"
            
            # WSL-specific GPU permissions
            print_status "Setting up WSL GPU permissions..."
            sudo chmod 666 /dev/dri/* 2>/dev/null || true
            sudo chmod 666 /dev/dxg 2>/dev/null || true
            export MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA
            
        else
            # Linux with NVIDIA
            print_status "Linux detected with NVIDIA GPU"
            
            # Check Docker version for GPU support
            if dpkg --compare-versions 19.03 gt "$DOCKER_VER" 2>/dev/null; then
                print_warning "Docker version < 19.03, using nvidia-docker2 runtime"
                if ! dpkg --list | grep nvidia-docker2 &> /dev/null; then
                    print_error "Please install nvidia-docker2 or update Docker to version >= 19.03"
                    exit 1
                fi
                DOCKER_OPTS="$DOCKER_OPTS --runtime=nvidia"
            else
                DOCKER_OPTS="$DOCKER_OPTS --gpus all"
            fi
            DOCKER_OPTS="$DOCKER_OPTS -e NVIDIA_DRIVER_CAPABILITIES=all"
        fi
    else
        print_warning "No NVIDIA GPU detected - running in CPU mode"
    fi
}

# Function to setup display
setup_display() {
    local os=$1
    
    if [[ "$os" == "wsl" ]]; then
        # WSL2 display setup
        print_status "Setting up WSL2 display forwarding..."
        DOCKER_OPTS="$DOCKER_OPTS -v /tmp/.X11-unix:/tmp/.X11-unix"
        DOCKER_OPTS="$DOCKER_OPTS -v /mnt/wslg:/mnt/wslg"
        DOCKER_OPTS="$DOCKER_OPTS -e DISPLAY=$DISPLAY"
        DOCKER_OPTS="$DOCKER_OPTS -e WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
        DOCKER_OPTS="$DOCKER_OPTS -e XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
        DOCKER_OPTS="$DOCKER_OPTS -e PULSE_SERVER=$PULSE_SERVER"
        
        # WSL GPU device access
        DOCKER_OPTS="$DOCKER_OPTS -v /usr/lib/wsl:/usr/lib/wsl"
        DOCKER_OPTS="$DOCKER_OPTS --device=/dev/dxg"
        DOCKER_OPTS="$DOCKER_OPTS -e LD_LIBRARY_PATH=/usr/lib/wsl/lib"
        DOCKER_OPTS="$DOCKER_OPTS --device /dev/dri/card0"
        DOCKER_OPTS="$DOCKER_OPTS --device /dev/dri/renderD128"
        DOCKER_OPTS="$DOCKER_OPTS -e MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA"
        
    else
        # Linux display setup
        print_status "Setting up Linux display forwarding..."
        
        # Setup X11 authentication
        XAUTH=/tmp/.docker.xauth
        xauth_list=$(xauth nlist :0 | sed -e 's/^..../ffff/' 2>/dev/null || true)
        
        if [[ ! -f $XAUTH ]]; then
            print_status "Creating X11 authentication file..."
            touch $XAUTH
            chmod a+r $XAUTH
            if [[ ! -z "$xauth_list" ]]; then
                echo $xauth_list | xauth -f $XAUTH nmerge - 2>/dev/null || true
            fi
        fi
        
        if [[ -f $XAUTH ]]; then
            DOCKER_OPTS="$DOCKER_OPTS --volume=/tmp/.X11-unix:/tmp/.X11-unix:rw"
            DOCKER_OPTS="$DOCKER_OPTS --volume=$XAUTH:$XAUTH"
            DOCKER_OPTS="$DOCKER_OPTS --env=XAUTHORITY=$XAUTH"
            DOCKER_OPTS="$DOCKER_OPTS --env=DISPLAY=$DISPLAY"
            DOCKER_OPTS="$DOCKER_OPTS --env=QT_X11_NO_MITSHM=1"
            
            # Allow X11 connections
            xhost +local:docker 2>/dev/null || true
        else
            print_warning "X11 authentication setup failed - GUI applications may not work"
        fi
    fi
}

# Main script
main() {
    print_status "PX4 ROS2 Jazzy Docker Environment"
    print_status "=================================="
    
    # Detect environment
    OS=$(detect_os)
    GPU=$(detect_gpu)
    
    print_status "Detected OS: $OS"
    print_status "Detected GPU: $GPU"
    
    # Configuration
    DOCKER_REPO="px4-dev-simulation-ubuntu24"
    CONTAINER_NAME="px4_ros2_jazzy"
    WORKSPACE_DIR=~/${CONTAINER_NAME}_shared_volume
    SUDO_PASSWORD="user"
    
    # Allow custom container name
    if [[ "$1" != "" ]]; then
        CONTAINER_NAME=$1
        WORKSPACE_DIR=~/${CONTAINER_NAME}_shared_volume
    fi
    
    # Create workspace directory
    if [[ ! -d $WORKSPACE_DIR ]]; then
        mkdir -p $WORKSPACE_DIR
        print_success "Created workspace directory: $WORKSPACE_DIR"
    fi
    
    print_status "Container name: $CONTAINER_NAME"
    print_status "Workspace directory: $WORKSPACE_DIR"
    
    # Initialize Docker options
    DOCKER_OPTS=""
    
    # Setup GPU support
    setup_gpu_support $OS $GPU
    
    # Setup display
    setup_display $OS
    
    # Common options
    DOCKER_OPTS="$DOCKER_OPTS --privileged"
    DOCKER_OPTS="$DOCKER_OPTS --network host"
    DOCKER_OPTS="$DOCKER_OPTS -e LOCAL_USER_ID=$(id -u)"
    DOCKER_OPTS="$DOCKER_OPTS -e FASTRTPS_DEFAULT_PROFILES_FILE=/usr/local/share/middleware_profiles/rtps_udp_profile.xml"
    DOCKER_OPTS="$DOCKER_OPTS --volume=$WORKSPACE_DIR:/home/user/shared_volume:rw"
    DOCKER_OPTS="$DOCKER_OPTS --volume=/dev:/dev"
    DOCKER_OPTS="$DOCKER_OPTS --workdir /home/user/shared_volume"
    
    # PX4-specific ports
    DOCKER_OPTS="$DOCKER_OPTS -p 14550:14550"
    DOCKER_OPTS="$DOCKER_OPTS -p 14556:14556"
    
    # ROS2 middleware
    DOCKER_OPTS="$DOCKER_OPTS -e RMW_IMPLEMENTATION=rmw_zenoh_cpp"
    
    print_status "Docker options: $DOCKER_OPTS"
    
    # Setup command
    CMD="export DEV_DIR=/home/user/shared_volume && \
        export PX4_DIR=\$DEV_DIR/PX4-Autopilot && \
        export ROS2_WS=\$DEV_DIR/ros2_ws && \
        export OSQP_SRC=\$DEV_DIR && \
        source /home/user/.bashrc && \
        if [ -f \"/home/user/shared_volume/ros2_ws/install/setup.bash\" ]; then \
            source /home/user/shared_volume/ros2_ws/install/setup.bash; \
        fi && \
        /bin/bash"
    
    # Add environment variables if available
    if [[ -n "$GIT_TOKEN" ]] && [[ -n "$GIT_USER" ]]; then
        CMD="export GIT_USER=$GIT_USER && export GIT_TOKEN=$GIT_TOKEN && $CMD"
    fi
    
    if [[ -n "$SUDO_PASSWORD" ]]; then
        CMD="export SUDO_PASSWORD=$SUDO_PASSWORD && $CMD"
    fi
    
    # Check if container exists
    if [[ "$(docker ps -aq -f name=^${CONTAINER_NAME}$)" ]]; then
        if [[ "$(docker ps -q -f name=^${CONTAINER_NAME}$)" ]]; then
            print_status "Container is already running. Attaching to it..."
            docker exec --user user -it $CONTAINER_NAME env TERM=xterm-256color bash -c "${CMD}"
        else
            print_status "Restarting the container..."
            docker start $CONTAINER_NAME
            docker exec --user user -it $CONTAINER_NAME env TERM=xterm-256color bash -c "${CMD}"
        fi
    else
        print_status "Creating and running new container..."
        docker run -it \
            --name $CONTAINER_NAME \
            $DOCKER_OPTS \
            ${DOCKER_REPO} \
            bash -c "${CMD}"
    fi
}

# Run main function
main "$@" 