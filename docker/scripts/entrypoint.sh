#!/bin/bash

# Start virtual X server in the background
# - DISPLAY default is :99, set in dockerfile
# - Users can override with `-e DISPLAY=` in `docker run` command to avoid
#   running Xvfb and attach their screen
if [[ -x "$(command -v Xvfb)" && "$DISPLAY" == ":99" ]]; then
	echo "Starting Xvfb"
	Xvfb :99 -screen 0 1600x1200x24+32 &
fi

# Export development environment variables
export DEV_DIR=/home/user/shared_volume
export PX4_DIR=$DEV_DIR/PX4-Autopilot
export ROS2_WS=$DEV_DIR/ros2_ws
export OSQP_SRC=$DEV_DIR

# Export additional environment variables if provided
if [[ -n "$GIT_TOKEN" ]] && [[ -n "$GIT_USER" ]]; then
    export GIT_USER=$GIT_USER
    export GIT_TOKEN=$GIT_TOKEN
fi

if [[ -n "$SUDO_PASSWORD" ]]; then
    export SUDO_PASSWORD=$SUDO_PASSWORD
fi

# Check if the ROS_DISTRO is passed and use it
# to source the ROS environment
if [ -n "${ROS_DISTRO}" ]; then
	source "/opt/ros/$ROS_DISTRO/setup.bash"
fi

# Source ROS2 workspace if it exists
if [ -f "/home/user/shared_volume/ros2_ws/install/setup.bash" ]; then
    source /home/user/shared_volume/ros2_ws/install/setup.bash
fi

# Use the LOCAL_USER_ID if passed in at runtime
if [ -n "${LOCAL_USER_ID}" ]; then
	echo "Starting with UID : $LOCAL_USER_ID"
	
	# Check if user exists with different UID
	if id user >/dev/null 2>&1; then
		# User exists, modify UID
		usermod -u $LOCAL_USER_ID user >/dev/null 2>&1 || true
	else
		# Create user if it doesn't exist
		useradd --shell /bin/bash -u $LOCAL_USER_ID -c "" -m user
		usermod -a -G dialout user
		echo "user:user" | chpasswd
		adduser user sudo
	fi
	
	# Handle LOCAL_GROUP_ID if provided
	if [ -n "${LOCAL_GROUP_ID}" ]; then
		echo "Starting with GID : $LOCAL_GROUP_ID"
		
		# Check if group exists
		if getent group user >/dev/null 2>&1; then
			groupmod -g $LOCAL_GROUP_ID user >/dev/null 2>&1 || true
		else
			groupadd -g $LOCAL_GROUP_ID user
			usermod -a -G user user
		fi
	fi
	
	# Ensure user is in necessary groups for device access
	usermod -a -G dialout,plugdev,video,audio,render user >/dev/null 2>&1 || true
	
	# Create shared volume directory if it doesn't exist
	mkdir -p /home/user/shared_volume
	
	# Change ownership of home directory and shared volume to user
	chown -R user:user /home/user
	
	# Set proper permissions for device access (WSL compatibility)
	if [ -d "/dev/dri" ]; then
		chmod 666 /dev/dri/* 2>/dev/null || true
	fi
	
	if [ -e "/dev/dxg" ]; then
		chmod 666 /dev/dxg 2>/dev/null || true
	fi
	
	# Source bashrc as user and run command
	exec gosu user bash -c "source /home/user/.bashrc && $@"
else
	exec "$@"
fi