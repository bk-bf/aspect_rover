# ASPECT (Autonomous Surface Precision Excavation for Celestial Terrain)

A ROS 2 Humble + Gazebo 11 simulation and physical prototype of a lunar mining rover designed for in-situ resource utilization (ISRU) on the Moon, with progressive testing from simulation to extreme Earth environments.

## Project Goals

This project aims to:

- Create a simulation-to-hardware pipeline for lunar regolith excavation using ROS 2 Humble and Gazebo 11 with Bekker-Wong terrain modeling
- Develop and validate a 1:10 scale rover prototype capable of excavating ≥5g/min of lunar regolith analog at <50W power consumption
- Test rover capabilities progressively through simulation, backyard tests, Arctic environment (Svalbard), and eventually Atacama Desert conditions
- Advance technology readiness level from TRL-3 to TRL-6 by 2028
- Establish technical foundations for future lunar hydrogen production capabilities (target: 10t/yr by 2032)
- Align development with NASA ISRU Strategic Plan and ESA Analog Handbook standards

## System Architecture

- **Simulation Environment**: ROS 2 Humble + Gazebo 11 with Bekker-Wong regolith plugin
- **Hardware Platform**: 
  - 1:10 scale rover chassis (3D printed in PETG/PLA+)
  - Motors: SG90 servos/Faulhaber 1524 motors
  - Computing: Raspberry Pi + GY-521 IMU
  - Vision: ESP32-CAM with OpenCV edge detection
  - Based on modified NASA Open-Source Rover design

## Development Roadmap

### 2025 Q1-Q2: Simulation Foundation

- ROS 2 Humble + Gazebo 11 environment setup with Bekker-Wong terrain modeling
- Development of lunar regolith excavation simulation model
- Creation of Harvesting Algorithm v0.5 for autonomous operation
- Simulation benchmarks: Virtual excavation rate ≥5g/min at <50W power consumption
- Data collection framework for performance metrics and optimization

### 2025 Q3-Q4: Hardware Prototyping \& Initial Testing

- Simulation-to-hardware transition as funding permits
- 1:10 scale prototype development using cost-effective components
- Backyard testing with volcanic ash (regolith analog)
- Integration of perception systems (ESP32-CAM with OpenCV)
- Benchmark: Process 50g volcanic ash in controlled environment

### 2026 Q1-Q2: Field Testing \& Environmental Validation

- Arctic testing at Svalbard (72h continuous operation)
- Sensor fusion implementation
- Target: 5kg/30min excavation benchmark
- TRL-3 validation through environmental testing

### 2026 Q3-Q4 and Beyond

- Atacama Desert field trials
- Electrostatic regolith separation testing
- Progressive scaling of prototype capabilities
- Collaboration with research institutions for advanced testing
- Scaling for eventual lunar deployment

## Dependencies

- ROS 2 Humble
- Gazebo 11
- Bekker-Wong terrain modeling plugin
- OpenCV
- Navigation2 stack

## Installation

### Prerequisites

Install ROS 2 Humble
Follow instructions at: https://docs.ros.org/en/humble/Installation.html

Install Gazebo 11
```bash
sudo apt update
sudo apt install gazebo11
```

### Building the Project

Create a workspace
```bash
mkdir -p ~/aspect_ws/src
cd ~/aspect_ws/src
```
Clone this repository
```bash
git clone https://github.com/bk-bf/aspect_ros2_gazebo11.git
```
Install dependencies
```bash
cd ~/aspect_ws
rosdep update
rosdep install --from-paths src --ignore-src -r -y
```
Build the workspace
```bash
colcon build
source install/setup.bash
```
## Usage

Launch the lunar rover simulation:
```bash
ros2 launch aspect_bringup lunar_sim.launch.py
```
## Project Structure

- `aspect_description/`: URDF model files for the rover
- `aspect_gazebo/`: Gazebo-specific configuration and lunar world files
- `aspect_control/`: Control algorithms for regolith excavation
- `aspect_navigation/`: Navigation and path planning for lunar terrain
- `aspect_bringup/`: Launch files and configuration

## Partners & Acknowledgments

- ROS 2 and Gazebo communities
- Contributors to the ros_gz packages
- ESA/NASA ISRU Strategic Plans

## License

This project is licensed under the MIT License - see the LICENSE file for details.


