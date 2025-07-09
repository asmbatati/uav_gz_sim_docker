#!/bin/bash
#
# Docker Compose runner for PX4 ROS2 development environment
# Automatically detects environment and applies appropriate profile
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
    if [[ -f /proc/version ]] && grep -q Microsoft /proc/version; then
        echo "wsl"
    else
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

# Function to setup environment
setup_environment() {
    local os=$1
    local gpu=$2
    
    print_status "Setting up environment for $os with $gpu GPU..."
    
    # Create workspace directory
    WORKSPACE_DIR=~/px4_ros2_jazzy_shared_volume
    if [[ ! -d $WORKSPACE_DIR ]]; then
        mkdir -p $WORKSPACE_DIR
        print_success "Created workspace directory: $WORKSPACE_DIR"
    fi
    
    # WSL-specific setup
    if [[ "$os" == "wsl" ]]; then
        print_status "Setting up WSL-specific configurations..."
        sudo chmod 666 /dev/dri/* 2>/dev/null || true
        sudo chmod 666 /dev/dxg 2>/dev/null || true
        export MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA
    fi
    
    # Linux X11 setup
    if [[ "$os" == "linux" ]]; then
        print_status "Setting up X11 display forwarding..."
        xhost +local:docker 2>/dev/null || true
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
    echo ""
    echo "Options:"
    echo "  --profile PROFILE    Use specific profile (gpu, cpu, xrce-agent, qgc, bridge)"
    echo "  --no-gpu            Force CPU-only mode"
    echo "  --with-qgc          Include QGroundControl"
    echo "  --with-xrce         Include XRCE-DDS Agent"
    echo "  --with-bridge       Include ROS2 Bridge"
    echo "  --help              Show this help message"
    echo ""
    echo "Profiles:"
    echo "  default             Main development environment"
    echo "  gpu                 With GPU acceleration"
    echo "  cpu                 CPU-only mode"
    echo "  xrce-agent          Include XRCE-DDS Agent"
    echo "  qgc                 Include QGroundControl"
    echo "  bridge              Include ROS2 Bridge"
    echo ""
    echo "Examples:"
    echo "  $0 up                    # Start with auto-detection"
    echo "  $0 up --profile gpu      # Start with GPU support"
    echo "  $0 up --with-qgc         # Start with QGroundControl"
    echo "  $0 shell                 # Open shell in container"
}

# Main function
main() {
    # Parse arguments
    COMMAND=""
    PROFILES=()
    FORCE_CPU=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            up|down|restart|logs|shell|build|clean)
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
    
    # Detect environment
    OS=$(detect_os)
    GPU=$(detect_gpu)
    
    if [[ "$FORCE_CPU" == "true" ]]; then
        GPU="none"
    fi
    
    print_status "PX4 ROS2 Jazzy Docker Compose Environment"
    print_status "=========================================="
    print_status "Detected OS: $OS"
    print_status "Detected GPU: $GPU"
    print_status "Command: $COMMAND"
    
    # Setup environment
    setup_environment $OS $GPU
    
    # Determine profiles
    if [[ ${#PROFILES[@]} -eq 0 ]]; then
        if [[ "$GPU" == "nvidia" ]]; then
            PROFILES=("gpu")
        else
            PROFILES=("cpu")
        fi
    fi
    
    print_status "Using profiles: ${PROFILES[*]}"
    
    # Execute command
    case $COMMAND in
        up)
            print_status "Starting services with profiles: ${PROFILES[*]}..."
            
            # Build profile arguments correctly
            PROFILE_ARGS=""
            for profile in "${PROFILES[@]}"; do
                PROFILE_ARGS="$PROFILE_ARGS --profile $profile"
            done
            
            print_status "Docker Compose command: docker-compose $PROFILE_ARGS up -d"
            
            # Check if Docker Compose is available
            if ! command -v docker-compose &> /dev/null; then
                print_error "docker-compose not found. Please install Docker Compose."
                exit 1
            fi
            
            # Start services
            docker-compose $PROFILE_ARGS up -d
            
            if [ $? -eq 0 ]; then
                print_success "Services started successfully!"
                print_status "Active containers:"
                docker-compose ps
                echo ""
                print_status "To access the main container: $0 shell"
                print_status "To view logs: $0 logs"
                print_status "To stop services: $0 down"
            else
                print_error "Failed to start services. Check the logs with: $0 logs"
                exit 1
            fi
            ;;
        down)
            print_status "Stopping all services..."
            docker-compose down
            if [ $? -eq 0 ]; then
                print_success "Services stopped successfully!"
            else
                print_error "Failed to stop some services."
                exit 1
            fi
            ;;
        restart)
            print_status "Restarting services..."
            
            # Get current profiles from running containers
            RUNNING_PROFILES=()
            if docker-compose ps --services 2>/dev/null | grep -q px4-dev-gpu; then
                RUNNING_PROFILES+=("gpu")
            elif docker-compose ps --services 2>/dev/null | grep -q px4-dev; then
                RUNNING_PROFILES+=("default")
            fi
            
            if docker-compose ps --services 2>/dev/null | grep -q xrce-agent; then
                RUNNING_PROFILES+=("xrce-agent")
            fi
            
            if docker-compose ps --services 2>/dev/null | grep -q mavros-bridge; then
                RUNNING_PROFILES+=("mavros")
            fi
            
            if docker-compose ps --services 2>/dev/null | grep -q qgroundcontrol; then
                RUNNING_PROFILES+=("qgc")
            fi
            
            if docker-compose ps --services 2>/dev/null | grep -q ros2-bridge; then
                RUNNING_PROFILES+=("bridge")
            fi
            
            # Use detected profiles or fallback to current PROFILES
            if [ ${#RUNNING_PROFILES[@]} -gt 0 ]; then
                PROFILES=("${RUNNING_PROFILES[@]}")
                print_status "Detected running profiles: ${PROFILES[*]}"
            fi
            
            # Build profile arguments
            PROFILE_ARGS=""
            for profile in "${PROFILES[@]}"; do
                PROFILE_ARGS="$PROFILE_ARGS --profile $profile"
            done
            
            docker-compose $PROFILE_ARGS restart
            
            if [ $? -eq 0 ]; then
                print_success "Services restarted successfully!"
            else
                print_error "Failed to restart services."
                exit 1
            fi
            ;;
        logs)
            print_status "Showing logs..."
            if [[ ${#PROFILES[@]} -gt 0 ]]; then
                PROFILE_ARGS=""
                for profile in "${PROFILES[@]}"; do
                    PROFILE_ARGS="$PROFILE_ARGS --profile $profile"
                done
                docker-compose $PROFILE_ARGS logs -f
            else
                docker-compose logs -f
            fi
            ;;
        shell)
            print_status "Opening shell in main container..."
            
            # Check if GPU container is running first
            if docker-compose ps px4-dev-gpu 2>/dev/null | grep -q "Up"; then
                print_status "Connecting to GPU-enabled container..."
                docker-compose exec px4-dev-gpu bash
            elif docker-compose ps px4-dev 2>/dev/null | grep -q "Up"; then
                print_status "Connecting to main container..."
                docker-compose exec px4-dev bash
            else
                print_error "No running px4-dev container found. Start services first with: $0 up"
                exit 1
            fi
            ;;
        build)
            print_status "Building Docker image..."
            cd docker 2>/dev/null || {
                print_error "Docker directory not found. Make sure you're in the px4_ros2_jazzy_docker directory."
                exit 1
            }
            
            if make px4-dev-simulation-ubuntu24; then
                print_success "Image built successfully!"
            else
                print_error "Failed to build Docker image."
                exit 1
            fi
            ;;
        clean)
            print_warning "This will remove ALL containers, volumes, and images!"
            read -p "Are you sure? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_status "Cleaning up..."
                
                # Stop and remove containers
                docker-compose down -v --remove-orphans 2>/dev/null || true
                
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