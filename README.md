# PX4 ROS2 Jazzy Docker Environment

A comprehensive Docker development environment for PX4 + ROS 2 Jazzy with full simulation support, compatible with both Linux and WSL2.

## What's Included

* **Ubuntu 24.04** - Latest LTS base
* **ROS 2 Jazzy Desktop Full** - Complete ROS2 development stack
* **Gazebo Harmonic** - Latest simulation environment
* **PX4 Development Tools** - Complete PX4 firmware development environment
* **XRCE-DDS Agent & Client** - PX4-ROS2 communication bridge
* **JSBSim** - Advanced flight dynamics model
* **VS Code** - Integrated development environment
* **Custom Simulation Models** - X500 drone with Intel RealSense D435
* **WSL2 Support** - Full GPU acceleration and display forwarding

## Prerequisites

### Linux
- Docker installed ([Ubuntu Docker installation guide](https://docs.docker.com/engine/install/ubuntu/))
- NVIDIA Docker support for GPU acceleration (optional but recommended)

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

This builds a comprehensive Docker image with the complete PX4 development environment, ROS 2 Jazzy Desktop, and Gazebo Harmonic simulation tools.

## Run the Container

### Option 1: Docker Compose (Recommended)

The Docker Compose setup provides the most flexible and powerful way to run the environment:

```bash
# Make the script executable
chmod +x docker-compose-run.sh

# Start with auto-detection (recommended)
./docker-compose-run.sh up

# Start with specific profiles
./docker-compose-run.sh up --profile gpu
./docker-compose-run.sh up --with-qgc
./docker-compose-run.sh up --with-xrce --with-bridge

# Access the container
./docker-compose-run.sh shell

# View logs
./docker-compose-run.sh logs

# Stop services
./docker-compose-run.sh down
```

#### Docker Compose Benefits:
- **Automatic Environment Detection**: Detects OS (Linux/WSL) and GPU availability
- **Service Profiles**: Choose which services to run (GPU, QGC, XRCE-Agent, Bridge)
- **Persistent Volumes**: Named volumes for data persistence
- **Service Orchestration**: Proper startup order and dependencies
- **Easy Management**: Simple commands for start/stop/restart/logs
- **Multi-Service Support**: Run additional services like QGroundControl

#### Available Profiles:
- `default` - Main development environment
- `gpu` - With GPU acceleration
- `cpu` - CPU-only mode
- `xrce-agent` - Include XRCE-DDS Agent service
- `qgc` - Include QGroundControl
- `bridge` - Include ROS2 Bridge service

### Option 2: Direct Docker Commands

#### Linux
```bash
# Standard run (CPU only)
./docker_run.sh

# For NVIDIA GPU support
./docker_run_nvidia.sh
```

#### WSL2 (Windows)
```bash
# WSL2 with full GPU support and display forwarding
./docker_run_wsl.sh
```

### Option 3: Unified Script

```bash
# Auto-detects environment and applies appropriate configuration
./docker_run_unified.sh
```

The WSL script automatically handles:
- GPU device permissions
- Display forwarding (X11/Wayland)
- WSL-specific device mounting
- NVIDIA GPU acceleration

## Container Details

* **Shared Volume**: Files persist in `$HOME/px4_ros2_jazzy_shared_volume` (host) ↔ `/home/user/shared_volume` (container)
* **User Credentials**: Username `user`, Password `user` (sudo access enabled)
* **Networking**: Host network mode for seamless ROS2 communication
* **Ports Exposed**: 14550, 14556 (PX4 MAVLink communication)

## Quick Start - PX4 Setup

1. **Enter the container**:
   ```bash
   # Using Docker Compose (recommended)
   ./docker-compose-run.sh up
   ./docker-compose-run.sh shell
   
   # Or using direct scripts
   ./docker_run_wsl.sh  # or ./docker_run.sh on Linux
   ```

2. **Navigate to shared volume**:
   ```bash
   cd /home/user/shared_volume
   ```

3. **Clone PX4-Autopilot**:
   ```bash
   git clone https://github.com/PX4/PX4-Autopilot.git --recursive
   cd PX4-Autopilot
   ```

4. **Build and test PX4 simulation**:
   ```bash
   make clean
   make px4_sitl gz_x500
   ```

5. **Run XRCE-DDS Agent** (if not using Docker Compose):
   ```bash
   MicroXRCEAgent udp4 -p 8888
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

Create and build ROS 2 packages as described in the [PX4-ROS2 documentation](https://docs.px4.io/main/en/ros/ros2_comm.html#build-ros-2-workspace).

The environment automatically sources:
- `/opt/ros/jazzy/setup.bash`
- `/home/user/shared_volume/ros2_ws/install/setup.bash` (if available)

## Examples and Tutorials

* [PX4 Offboard Control](https://github.com/Jaeyoung-Lim/px4-offboard)
  - Use `MicroXRCEAgent udp4 -p 8888` for the agent
  - Use `make px4_sitl gz_x500` for simulation
  - QGroundControl can run on the host system

## Additional Resources

* [Gazebo Fuel](https://app.gazebosim.org/fuel) - Library of simulation worlds and models
* [PX4 User Guide](https://docs.px4.io/main/en/) - Complete PX4 documentation
* [ROS 2 Documentation](https://docs.ros.org/en/jazzy/) - ROS 2 Jazzy resources

## Troubleshooting

### WSL2 Issues
- Ensure WSLg is enabled: `wsl --update`
- Check GPU support: `nvidia-smi` should work in WSL
- Verify display: `echo $DISPLAY` should show a value

### Linux Issues
- For NVIDIA GPU: Install `nvidia-docker2` package
- For display issues: Run `xhost +local:docker` before starting container

### Container Issues
- Check Docker daemon is running
- Ensure sufficient disk space for the large simulation image
- Verify shared volume permissions

### Docker Compose Issues
- Ensure Docker Compose is installed: `docker-compose --version`
- Check profiles are correctly specified
- Use `./docker-compose-run.sh logs` to debug service issues