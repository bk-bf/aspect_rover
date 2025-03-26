# filepath: /home/kirill/Documents/vs_code_ws/aspect_rover/src/aspect_bringup/setup.py
from setuptools import setup
import os
from glob import glob


package_name = 'aspect_bringup'

setup(
    name=package_name,
    version='0.0.0',
    packages=[package_name],
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        # Install the launch directory
        (os.path.join('share', package_name, 'launch'), glob('launch/*.py')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='kirill',
    maintainer_email='boychenkokirill@gmail.com',
    description='Launch files for the Aspect Rover project',
    license='Apache License 2.0',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
        ],
    },
)
