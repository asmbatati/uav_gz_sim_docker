#!/bin/bash
#
# Enhanced Docker Compose runner for PX4 ROS2 development environment
# Automatically detects environment and applies appropriate profile
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
    if [[ -f /proc/version ]] && grep -qi microsoft /proc/version; then
        echo "wsl"
    elif [[ -f /proc/sys/kernel/osrelease ]] && grep -qi microsoft /proc/sys/kernel/osrelease; then
        echo "wsl"
    elif [[ -n "$WSL_DISTRO_NAME" ]] || [[ -n "$WSL_INTEROP" ]]; then
        echo "wsl"
    elif [[ -d /mnt/wslg ]] || [[ -d /mnt/c ]] || [[ -d /mnt/wsl ]]; then
        echo "wsl"
    else
        echo "linux"
    fi
}

# Function to detect GPU with enhanced CUDA detection
detect_gpu() {
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

# Function to check Docker and Docker Compose
check_docker_compose() {
    print_status "Checking Docker and Docker Compose..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        local compose_version=$(docker-compose version --short 2>/dev/null || echo "unknown")
        print_success "Docker Compose version: $compose_version"
    elif docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        local compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        print_success "Docker Compose (plugin) version: $compose_version"
    else
        print_error "Docker Compose is not installed. Please install Docker Compose."
        exit 1
    fi
}

# Function to setup environment with enhanced error handling
setup_environment() {
    local os=$1
    local gpu=$2
    
    print_status "Setting up environment for $os with $gpu GPU..."
    
    # Create workspace directory with proper path resolution
    local workspace_dir
    
    # Get the absolute path to the shared volume directory
    # From px4_ros2_jazzy_docker directory: go up to ros2_ws/src/uav_gz_sim/px4_ros2_jazzy_docker
    # Then go up 4 levels to get to px4_ros2_jazzy_shared_volume
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    workspace_dir="$(cd "$script_dir" && cd ../../../.. && pwd)"
    
    # Fallback to home directory if path resolution fails
    if [[ ! -d "$workspace_dir" ]] || [[ "$(basename "$workspace_dir")" != "px4_ros2_jazzy_shared_volume" ]]; then
        print_warning "Could not resolve workspace path, using fallback"
        workspace_dir="$HOME/px4_ros2_jazzy_shared_volume"
    fi
    
    # Create directory if it doesn't exist
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
    
    # Export environment variables for Docker Compose
    export LOCAL_USER_ID=$(id -u)
    export LOCAL_GROUP_ID=$(id -g)
    export DISPLAY="${DISPLAY:-:0}"
    export WORKSPACE_DIR="$workspace_dir"
    
    # WSL-specific setup
    if [[ "$os" == "wsl" ]]; then
        print_status "Setting up WSL-specific configurations..."
        
        # WSL display and GPU setup
        export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
        export PULSE_SERVER="${PULSE_SERVER:-unix:/tmp/pulse-socket}"
        
        # WSL GPU permissions
        if [[ -d /dev/dri ]]; then
            sudo chmod 666 /dev/dri/* 2>/dev/null || print_warning "Could not set DRI permissions"
        fi
        
        if [[ -e /dev/dxg ]]; then
            sudo chmod 666 /dev/dxg 2>/dev/null || print_warning "Could not set DXG permissions"
        fi
        
        print_success "WSL environment configured"
    fi
    
    # Linux X11 setup
    if [[ "$os" == "linux" ]]; then
        print_status "Setting up X11 display forwarding..."
        
        # Setup X11 authentication
        if command -v xhost &> /dev/null; then
            xhost +local:docker 2>/dev/null || print_warning "Could not configure xhost"
        fi
        
        # Setup X11 auth file
        if [[ -n "$DISPLAY" ]] && command -v xauth &> /dev/null; then
            XAUTH_FILE="$HOME/.Xauthority"
            if [[ -f "$XAUTH_FILE" ]]; then
                export XAUTHORITY="$XAUTH_FILE"
                print_success "X11 authentication configured"
            fi
        fi
        
        print_success "Linux display environment configured"
    fi
    
    print_success "Environment setup completed"
}

# Function to get Docker Compose file path
get_compose_file() {
    local compose_file="docker-compose.yml"
    
    if [[ -f "$compose_file" ]]; then
        echo "$compose_file"
    else
        print_error "Docker Compose file not found: $compose_file"
        print_error "Please run this script from the px4_ros2_jazzy_docker directory"
        exit 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  up              Start the development environment"
    echo "  down            Stop all services"
    echo "  restart         Restart all services"
    echo "  logs            Show logs from all services"
    echo "  shell           Open shell in main container"
    echo "  build           Build the Docker image"
    echo "  clean           Remove all containers and volumes"
    echo "  status          Show status of all services"
    echo ""
    echo "Options:"
    echo "  --profile PROFILE    Use specific profile (gpu, cpu, xrce-agent, qgc, bridge, mavros)"
    echo "  --no-gpu            Force CPU-only mode"
    echo "  --with-qgc          Include QGroundControl"
    echo "  --with-xrce         Include XRCE-DDS Agent"
    echo "  --with-mavros       Include MAVROS bridge"
    echo "  --with-bridge       Include ROS2 Bridge"
    echo "  --help              Show this help message"
    echo ""
    echo "Profiles:"
    echo "  default             Main development environment (CPU)"
    echo "  gpu                 With GPU acceleration (NVIDIA)"
    echo "  cpu                 CPU-only mode"
    echo "  xrce-agent          Include XRCE-DDS Agent"
    echo "  mavros              Include MAVROS bridge"
    echo "  qgc                 Include QGroundControl"
    echo "  bridge              Include ROS2 Bridge"
    echo ""
    echo "Examples:"
    echo "  $0 up                    # Start with auto-detection"
    echo "  $0 up --profile gpu      # Start with GPU support"
    echo "  $0 up --with-qgc         # Start with QGroundControl"
    echo "  $0 up --with-mavros      # Start with MAVROS bridge"
    echo "  $0 shell                 # Open shell in container"
    echo "  $0 logs                  # Show logs"
    echo "  $0 status                # Show service status"
}

# Function to build profile arguments
build_profile_args() {
    local profiles=("$@")
    local profile_args=""
    
    for profile in "${profiles[@]}"; do
        profile_args="$profile_args --profile $profile"
    done
    
    echo "$profile_args"
}

# Function to detect running profiles
detect_running_profiles() {
    local compose_file=$1
    local running_profiles=()
    
    # Check which services are running
    if $COMPOSE_CMD -f "$compose_file" ps --services 2>/dev/null | grep -q "px4-dev-gpu"; then
        running_profiles+=("gpu")
    elif $COMPOSE_CMD -f "$compose_file" ps --services 2>/dev/null | grep -q "px4-dev"; then
        running_profiles+=("default")
    fi
    
    if $COMPOSE_CMD -f "$compose_file" ps --services 2>/dev/null | grep -q "xrce-agent"; then
        running_profiles+=("xrce-agent")
    fi
    
    if $COMPOSE_CMD -f "$compose_file" ps --services 2>/dev/null | grep -q "mavros-bridge"; then
        running_profiles+=("mavros")
    fi
    
    if $COMPOSE_CMD -f "$compose_file" ps --services 2>/dev/null | grep -q "qgroundcontrol"; then
        running_profiles+=("qgc")
    fi
    
    if $COMPOSE_CMD -f "$compose_file" ps --services 2>/dev/null | grep -q "ros2-bridge"; then
        running_profiles+=("bridge")
    fi
    
    echo "${running_profiles[@]}"
}

# Main function
main() {
    # Parse arguments
    COMMAND=""
    PROFILES=()
    FORCE_CPU=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            up|down|restart|logs|shell|build|clean|status)
                COMMAND="$1"
                shift
                ;;
            --profile)
                PROFILES+=("$2")
                shift 2
                ;;
            --no-gpu)
                FORCE_CPU=true
                shift
                ;;
            --with-qgc)
                PROFILES+=("qgc")
                shift
                ;;
            --with-xrce)
                PROFILES+=("xrce-agent")
                shift
                ;;
            --with-mavros)
                PROFILES+=("mavros")
                shift
                ;;
            --with-bridge)
                PROFILES+=("bridge")
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Default command
    if [[ -z "$COMMAND" ]]; then
        COMMAND="up"
    fi
    
    print_header "PX4 ROS2 Jazzy Docker Compose Environment"
    
    # Check Docker and Docker Compose
    check_docker_compose
    
    # Get compose file
    COMPOSE_FILE=$(get_compose_file)
    print_success "Using Docker Compose file: $COMPOSE_FILE"
    
    # Detect environment
    OS=$(detect_os)
    GPU=$(detect_gpu)
    
    if [[ "$FORCE_CPU" == "true" ]]; then
        GPU="none"
    fi
    
    print_status "Detected OS: $OS"
    print_status "Detected GPU: $GPU"
    print_status "Command: $COMMAND"
    
    # Setup environment
    setup_environment "$OS" "$GPU"
    
    # Determine profiles if not specified
    if [[ ${#PROFILES[@]} -eq 0 ]]; then
        if [[ "$GPU" == "nvidia" ]]; then
            PROFILES=("gpu")
        else
            PROFILES=("default")
        fi
    fi
    
    print_status "Using profiles: ${PROFILES[*]}"
    
    # Build profile arguments
    PROFILE_ARGS=$(build_profile_args "${PROFILES[@]}")
    
    # Execute command
    case $COMMAND in
        up)
            print_status "Starting services with profiles: ${PROFILES[*]}..."
            
            print_status "Docker Compose command: $COMPOSE_CMD -f $COMPOSE_FILE $PROFILE_ARGS up -d"
            
            # Start services
            if $COMPOSE_CMD -f "$COMPOSE_FILE" $PROFILE_ARGS up -d; then
                print_success "Services started successfully!"
                echo
                print_status "Active containers:"
                $COMPOSE_CMD -f "$COMPOSE_FILE" ps
                echo
                print_status "Useful commands:"
                echo "  $0 shell                 # Open shell in main container"
                echo "  $0 logs                  # Show logs"
                echo "  $0 status                # Show service status"
                echo "  $0 down                  # Stop services"
                echo
                print_status "To run the install script:"
                echo "  $0 shell"
                echo "  cd /home/user/shared_volume/ros2_ws/src/uav_gz_sim && ./install.sh"
            else
                print_error "Failed to start services. Check the logs with: $0 logs"
                exit 1
            fi
            ;;
        down)
            print_status "Stopping all services..."
            if $COMPOSE_CMD -f "$COMPOSE_FILE" down; then
                print_success "Services stopped successfully!"
            else
                print_error "Failed to stop some services."
                exit 1
            fi
            ;;
        restart)
            print_status "Restarting services..."
            
            # Get current profiles from running containers
            RUNNING_PROFILES=($(detect_running_profiles "$COMPOSE_FILE"))
            
            # Use detected profiles or fallback to current PROFILES
            if [[ ${#RUNNING_PROFILES[@]} -gt 0 ]]; then
                PROFILES=("${RUNNING_PROFILES[@]}")
                print_status "Detected running profiles: ${PROFILES[*]}"
            fi
            
            # Build profile arguments
            PROFILE_ARGS=$(build_profile_args "${PROFILES[@]}")
            
            if $COMPOSE_CMD -f "$COMPOSE_FILE" $PROFILE_ARGS restart; then
                print_success "Services restarted successfully!"
            else
                print_error "Failed to restart services."
                exit 1
            fi
            ;;
        logs)
            print_status "Showing logs..."
            if [[ ${#PROFILES[@]} -gt 0 ]]; then
                PROFILE_ARGS=$(build_profile_args "${PROFILES[@]}")
                $COMPOSE_CMD -f "$COMPOSE_FILE" $PROFILE_ARGS logs -f
            else
                $COMPOSE_CMD -f "$COMPOSE_FILE" logs -f
            fi
            ;;
        shell)
            print_status "Opening shell in main container..."
            
            # Check if GPU container is running first
            if $COMPOSE_CMD -f "$COMPOSE_FILE" ps px4-dev-gpu 2>/dev/null | grep -q "Up"; then
                print_status "Connecting to GPU-enabled container..."
                $COMPOSE_CMD -f "$COMPOSE_FILE" exec px4-dev-gpu bash
            elif $COMPOSE_CMD -f "$COMPOSE_FILE" ps px4-dev 2>/dev/null | grep -q "Up"; then
                print_status "Connecting to main container..."
                $COMPOSE_CMD -f "$COMPOSE_FILE" exec px4-dev bash
            else
                print_error "No running px4-dev container found. Start services first with: $0 up"
                exit 1
            fi
            ;;
        build)
            print_status "Building Docker image..."
            
            # Check if docker directory exists
            if [[ ! -d "docker" ]]; then
                print_error "Docker directory not found. Make sure you're in the px4_ros2_jazzy_docker directory."
                exit 1
            fi
            
            # Build using Docker Compose
            if $COMPOSE_CMD -f "$COMPOSE_FILE" build; then
                print_success "Image built successfully!"
            else
                print_error "Failed to build Docker image."
                exit 1
            fi
            ;;
        status)
            print_status "Service status:"
            $COMPOSE_CMD -f "$COMPOSE_FILE" ps
            echo
            print_status "Docker containers:"
            docker ps --filter "label=com.docker.compose.project=$(basename "$PWD")" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            ;;
        clean)
            print_warning "This will remove ALL containers, volumes, and images!"
            read -p "Are you sure? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_status "Cleaning up..."
                
                # Stop and remove containers
                $COMPOSE_CMD -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
                
                # Remove the specific image
                docker rmi px4-dev-simulation-ubuntu24 2>/dev/null || true
                
                # Clean up Docker system
                docker system prune -f --volumes
                
                print_success "Cleanup completed!"
            else
                print_status "Cleanup cancelled."
            fi
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@" 