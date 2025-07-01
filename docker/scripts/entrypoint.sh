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
	# modify existing user's id
	usermod -u $LOCAL_USER_ID user
	
	# Handle LOCAL_GROUP_ID if provided
	if [ -n "${LOCAL_GROUP_ID}" ]; then
		echo "Starting with GID : $LOCAL_GROUP_ID"
		groupmod -g $LOCAL_GROUP_ID user
	fi
	
	# Change ownership of home directory to user
	chown -R user:user /home/user
	
	# Source bashrc as user and run command
	exec gosu user bash -c "source /home/user/.bashrc && $@"
else
	exec "$@"
fi