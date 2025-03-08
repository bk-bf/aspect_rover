# Rover ROS2 Gazebo11

A simulation environment for an autonomous rover using ROS 2 Humble and Gazebo 11, featuring navigation, control, and sensor integration capabilities.

## Overview

This project provides a complete simulation setup for a skid-steer rover platform. It includes the rover model, simulation environment, and ROS 2 integration for control and sensing. The repository is structured to facilitate both simulation experiments and eventual deployment to physical hardware.

## Features

- Fully simulated rover model in Gazebo 11
- ROS 2 - Gazebo bridge integration
- Navigation and path planning capabilities
- Simulated sensors (LiDAR, cameras, IMU)
- Teleop control options
- Autonomous navigation examples

## Dependencies

- ROS 2 Humble
- Gazebo 11
- ros_gz packages for ROS 2 - Gazebo integration
- Navigation2 stack

## Installation

### Prerequisites

Install ROS 2 Humble (if not already installed)
Follow instructions at: https://docs.ros.org/en/humble/Installation.html
Install Gazebo 11

sudo apt update
sudo apt install gazebo

### Building the Project

Create a workspace

mkdir -p ~/rover_ws/src
cd ~/rover_ws/src
Clone this repository

git clone https://github.com/yourusername/rover_ros2_gazebo11.git
Install dependencies

cd ~/rover_ws
rosdep update
rosdep install --from-paths src --ignore-src -r -y
Build the workspace

colcon build
source install/setup.bash

## Usage

Launch the rover simulation:
ros2 launch rover_bringup rover_sim.launch.py

For teleop control:
ros2 run teleop_twist_keyboard teleop_twist_keyboard


## Project Structure

- `rover_description/`: URDF model files for the rover
- `rover_gazebo/`: Gazebo-specific configuration and world files
- `rover_control/`: Control algorithms and parameters
- `rover_navigation/`: Navigation configuration and maps
- `rover_bringup/`: Launch files and configuration for bringing up the system

## Development

When developing new features:

1. Create a new branch: `git checkout -b feature/your-feature-name`
2. Make your changes and test thoroughly
3. Commit your changes with descriptive messages
4. Push to your fork and submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- ROS 2 and Gazebo communities
- Contributors to the ros_gz packages


