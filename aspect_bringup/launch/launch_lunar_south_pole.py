from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch.actions import ExecuteProcess
import os  # Import os to get the home directory

def generate_launch_description():
    # Dynamically get the home directory
    home_dir = os.path.expanduser('~')


    return LaunchDescription([
        # Declare the path to the world file
        DeclareLaunchArgument(
            'world',
            default_value=f'{home_dir}/Documents/vs_code_ws/aspect_rover/src/aspect_gazebo/worlds/lunar_south_pole.world',
            description='Path to the world file'
        ),

        # Launch Gazebo with the specified world file
        ExecuteProcess(
            cmd=[
                'ign', 'gazebo',
                '-v', '4',  # Verbosity level
                LaunchConfiguration('world')
            ],
            output='screen'
        )
    ])