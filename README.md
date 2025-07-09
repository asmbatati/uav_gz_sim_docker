# PX4 ROS2 Jazzy Docker Environment

A comprehensive Docker development environment for PX4 + ROS 2 Jazzy + MAVROS with full simulation support, compatible with both Linux and WSL2.

## What's Included

* **Ubuntu 24.04** - Latest LTS base
* **ROS 2 Jazzy Desktop Full** - Complete ROS2 development stack
* **Gazebo Harmonic** - Latest simulation environment
* **PX4 Development Tools** - Complete PX4 firmware development environment
* **MAVROS** - MAVLink-ROS 2 communication bridge
* **XRCE-DDS Agent & Client** - Native PX4-ROS2 communication bridge
* **Zenoh Middleware** - High-performance communication middleware
* **JSBSim** - Advanced flight dynamics model
* **VS Code** - Integrated development environment
* **Custom Simulation Models** - X500 drone with Intel RealSense D435
* **QGroundControl Support** - Ground control station integration
* **WSL2 Support** - Full GPU acceleration and display forwarding

## Prerequisites

### Linux
- Docker installed ([Ubuntu Docker installation guide](https://docs.docker.com/engine/install/ubuntu/))
- NVIDIA Docker support for GPU acceleration (optional but recommended)
- Docker Compose v2.0+ ([Installation guide](https://docs.docker.com/compose/install/))

### WSL2 (Windows)
- WSL2 with Ubuntu 22.04/24.04
- Docker Desktop with WSL2 backend
- NVIDIA GPU drivers for WSL2 (for GPU acceleration)
- WSLg for GUI applications

## Build Docker Image

```bash
git clone https://github.com/your-username/px4_ros2_jazzy_docker
cd px4_ros2_jazzy_docker/docker
make px4-dev-simulation-ubuntu24
```

This builds a comprehensive Docker image with:
- Complete PX4 development environment
- ROS 2 Jazzy Desktop with MAVROS
- Gazebo Harmonic simulation tools
- All necessary communication bridges

## Run the Container

### Option 1: Docker Compose (Recommended)

The Docker Compose setup provides the most flexible and powerful way to run the environment with improved error handling and service management:

```bash
# Make the script executable
chmod +x docker-compose-run.sh

# Start with auto-detection (recommended)
./docker-compose-run.sh up

# Start with specific configurations
./docker-compose-run.sh up --profile gpu           # GPU acceleration
./docker-compose-run.sh up --with-qgc              # Include QGroundControl
./docker-compose-run.sh up --with-mavros           # Include MAVROS bridge
./docker-compose-run.sh up --with-xrce             # Include XRCE-DDS Agent
./docker-compose-run.sh up --with-bridge           # Include ROS2-Gazebo bridge

# Access the container
./docker-compose-run.sh shell

# View logs with error details
./docker-compose-run.sh logs

# Stop services
./docker-compose-run.sh down
```

#### Docker Compose Benefits:
- **Automatic Environment Detection**: Detects OS (Linux/WSL) and GPU availability
- **Service Profiles**: Choose which services to run (GPU, QGC, MAVROS, XRCE-Agent, Bridge)
- **Persistent Volumes**: Named volumes for data persistence  
- **Service Orchestration**: Proper startup order and dependencies
- **Easy Management**: Simple commands for start/stop/restart/logs
- **Error Handling**: Robust error detection and recovery
- **Multi-Service Support**: Run additional services like QGroundControl and MAVROS

#### Available Profiles:
- `default` - Main development environment
- `gpu` - With GPU acceleration (auto-detected)
- `mavros` - Include MAVROS bridge service
- `xrce-agent` - Include XRCE-DDS Agent service
- `qgc` - Include QGroundControl
- `bridge` - Include ROS2-Gazebo Bridge service

### Option 2: Direct Docker Commands

#### Auto-Detection Script (Recommended)
```bash
# Auto-detects environment and applies appropriate configuration
./docker_run.sh
```

#### Manual Platform Selection
```bash
# Linux
./docker_run.sh

# WSL2 (Windows) - now handled automatically
./docker_run.sh
```

The unified script automatically handles:
- **Environment Detection**: Linux vs WSL2
- **GPU Support**: NVIDIA GPU detection and configuration
- **Display Forwarding**: X11/Wayland setup
- **Device Access**: Safe device mounting with error handling
- **Permission Management**: Proper user/group setup

## Container Details

* **Shared Volume**: Files persist in `$HOME/px4_ros2_jazzy_shared_volume` (host) ↔ `/home/user/shared_volume` (container)
* **User Credentials**: Username `user`, Password `user` (sudo access enabled)
* **Networking**: Host network mode for seamless ROS2 communication
* **Ports Exposed**: 
  - 14550, 14556, 14557 (PX4 MAVLink communication)
  - 8888 (XRCE-DDS Agent)
  - 5760 (QGroundControl)
* **Communication**: Both MAVROS and XRCE-DDS bridges available

## Quick Start - PX4 Setup

1. **Enter the container**:
   ```bash
   # Using Docker Compose (recommended)
   ./docker-compose-run.sh up
   ./docker-compose-run.sh shell
   
   # Or using direct scripts
   ./docker_run.sh
   ```

2. **Navigate to shared volume**:
   ```bash
   cd /home/user/shared_volume
   ```

3. **Clone and setup the simulation environment**:
   ```bash
   # Clone the complete simulation repository
   mkdir -p ros2_ws/src && cd ros2_ws/src
   git clone https://github.com/asmbatati/uav_gz_sim.git
   cd uav_gz_sim
   
   # Set environment variables
   export DEV_DIR=/home/user/shared_volume
   export GIT_USER=your_github_username  # Optional
   export GIT_TOKEN=your_github_token    # Optional
   
   # Run the installation script
   chmod +x install.sh
   ./install.sh  # Password is "user" if asked
   ```

4. **Test the simulation**:
   ```bash
   # Launch simulation
   source ~/shared_volume/ros2_ws/install/setup.bash
   ros2 launch uav_gz_sim sim.launch.py
   
   # In another terminal, start PX4 SITL
   cd ~/shared_volume/PX4-Autopilot
   make px4_sitl gz_x500_stereo_cam_3d_lidar
   ```

## Communication Bridges

The environment supports both communication architectures:

### XRCE-DDS (Native PX4-ROS2 Bridge)
```bash
# Start XRCE-DDS Agent (if not using Docker Compose)
MicroXRCEAgent udp4 -p 8888

# PX4 will automatically connect when launched
```

### MAVROS (MAVLink Bridge)
```bash
# Start MAVROS bridge (if not using Docker Compose)
ros2 launch mavros px4.launch fcu_url:=udp://:14540@127.0.0.1:14557

# Or start the MAVROS service via Docker Compose
./docker-compose-run.sh up --with-mavros
```

## Custom Simulation Models

The environment includes custom simulation assets in the `simulation/` folder:

- **X500 with RealSense D435**: Complete drone model for computer vision development
- **Intel RealSense D435**: Standalone depth camera sensor model
- **Realistic meshes and materials**: High-fidelity visual simulation

### Using Custom Models

```bash
# Launch X500 with D435 camera
make px4_sitl gz_x500_d435

# The model configuration is in simulation/models/x500_d435/
```

## ROS 2 Workspace Development

The environment automatically sources:
- `/opt/ros/jazzy/setup.bash`
- `/home/user/shared_volume/ros2_ws/install/setup.bash` (if available)

Both MAVROS and native PX4-ROS2 packages are pre-built and ready to use.

## Examples and Tutorials

* [PX4 Offboard Control](https://github.com/Jaeyoung-Lim/px4-offboard)
  - Use `MicroXRCEAgent udp4 -p 8888` for XRCE-DDS communication
  - Use `ros2 launch mavros px4.launch` for MAVROS communication
  - Use `make px4_sitl gz_x500` for simulation
  - QGroundControl can run via Docker service or on host system

## Troubleshooting

### WSL2 Issues
- Ensure WSLg is enabled: `wsl --update`
- Check GPU support: `nvidia-smi` should work in WSL
- Verify display: `echo $DISPLAY` should show a value
- Check device permissions: Docker script will attempt to fix automatically

### Linux Issues
- For NVIDIA GPU: Install `nvidia-docker2` package or use Docker 19.03+
- For display issues: Run `xhost +local:docker` before starting container
- Check device access: Ensure `/dev/dri` exists for GPU acceleration

### Container Issues
- Check Docker daemon is running: `sudo systemctl status docker`
- Ensure sufficient disk space for the simulation image (>10GB)
- Verify shared volume permissions: Script handles automatically
- Use `./docker-compose-run.sh logs` for detailed error information

### Docker Compose Issues
- Ensure Docker Compose v2.0+ is installed: `docker-compose --version`
- Check profiles are correctly specified in command
- Use `./docker-compose-run.sh logs` to debug service issues
- Services will automatically restart unless stopped

### Communication Issues
- **MAVROS**: Check PX4 is outputting MAVLink on port 14557
- **XRCE-DDS**: Ensure agent is running on port 8888
- **Port conflicts**: Stop other MAVLink applications before starting
- **Network**: Host networking mode should resolve most connectivity issues

## Advanced Usage

### Multiple Communication Bridges
```bash
# Run both MAVROS and XRCE-DDS simultaneously
./docker-compose-run.sh up --with-mavros --with-xrce

# This allows you to:
# - Use MAVROS for legacy applications
# - Use XRCE-DDS for high-performance applications
# - Compare performance between both bridges
```

### Custom Service Configurations
Edit `docker-compose.yml` to customize:
- Port mappings
- Environment variables
- Volume mounts
- Service dependencies

### Performance Optimization
- Use `--profile gpu` for hardware acceleration
- Increase Docker memory limits for complex simulations
- Use host networking for minimal latency
- Consider running QGroundControl on host for better GUI performance

## Additional Resources

* [PX4 User Guide](https://docs.px4.io/main/en/) - Complete PX4 documentation
* [ROS 2 Documentation](https://docs.ros.org/en/jazzy/) - ROS 2 Jazzy resources
* [MAVROS Documentation](https://github.com/mavlink/mavros) - MAVROS setup and usage
* [Gazebo Fuel](https://app.gazebosim.org/fuel) - Library of simulation worlds and models
* [uav_gz_sim Repository](https://github.com/asmbatati/uav_gz_sim) - Complete simulation framework