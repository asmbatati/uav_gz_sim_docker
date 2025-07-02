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
            docker-compose --profile $(IFS=,; echo "${PROFILES[*]}") up -d
            print_success "Services started successfully!"
            print_status "To access the container: $0 shell"
            ;;
        down)
            print_status "Stopping all services..."
            docker-compose down
            print_success "Services stopped successfully!"
            ;;
        restart)
            print_status "Restarting services..."
            docker-compose restart
            print_success "Services restarted successfully!"
            ;;
        logs)
            print_status "Showing logs..."
            docker-compose logs -f
            ;;
        shell)
            print_status "Opening shell in main container..."
            docker-compose exec px4-dev bash
            ;;
        build)
            print_status "Building Docker image..."
            docker-compose build
            print_success "Image built successfully!"
            ;;
        clean)
            print_warning "This will remove ALL containers and volumes!"
            read -p "Are you sure? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_status "Cleaning up..."
                docker-compose down -v --remove-orphans
                docker system prune -f
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