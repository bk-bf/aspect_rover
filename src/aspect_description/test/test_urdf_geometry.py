# Copyright 2026 Kirill Boychenko
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""
URDF geometry sanity checks — run via colcon test, no display required.

Catches structural issues in the URDF before any sim launch:

    T-G1  No collision geometry intersects z < GROUND_TOLERANCE at spawn.
           Spawning collision meshes far underground causes Gazebo DARTsim to
           apply large corrective impulses that destabilise rover physics.
           (Encountered with auger_housing_link, fixed in commit 7bda22d.)

    T-G2  Every non-fixed joint parent link exists in the kinematic tree.

    T-G3  Prismatic joint lower limits are >= 0 when axis points downward (-Z),
           i.e. the joint cannot pull a link further underground at spawn.

    T-G4  Every link in the URDF is reachable from the root (no orphans).

Ground-tolerance note
---------------------
GROUND_TOLERANCE is set to -(wheel_radius + 5mm) = -0.025 m.  The chassis box
(base_link) currently extends to -0.02 m because the box is centred on
base_link (world z = +0.02) with a half-extent of 0.04 m; this 2 cm overlap
with the ground plane is harmless in practice because wheel-ground contact
drives the physics.  Setting the tolerance below -0.02 m prevents this from
generating a false positive while still catching deeply embedded links (the
original auger bug reached -0.10 m).

Method
------
* ``xacro.process_file`` resolves all xacro properties so all values are real.
* BFS over the joint tree builds a world-z map at the spawn configuration
  (every prismatic joint at its lower limit; all others at their origin).
* For each link with ``<collision>``, the lowest z-extent of its geometry is
  compared against GROUND_TOLERANCE.

Limitations
-----------
* Only the Z axis is tracked — collision geometry that is rotated into the
  ground via non-zero RPY joints would not be detected.  Acceptable for the
  current axis-aligned URDF.
* Mesh geometries are skipped (no lightweight bound available at test time).
"""

import os
import xml.etree.ElementTree as ET

import pytest
import xacro

# Threshold: -(wheel_radius) - 5 mm safety margin.
# The chassis box legitimately extends to -0.02 m (see module docstring).
# This tolerance permits that while still catching the auger class of bug.
GROUND_TOLERANCE = -0.025

XACRO_PATH = os.path.join(
    os.path.dirname(__file__), '..', 'urdf', 'aspect_rover.urdf.xacro'
)


# ── helpers ──────────────────────────────────────────────────────────────────

def _parse_origin_z(element):
    """Return the z component of an ``<origin xyz="x y z">`` element, or 0."""
    if element is None:
        return 0.0
    xyz_str = element.get('xyz', '0 0 0')
    parts = xyz_str.split()
    try:
        return float(parts[2]) if len(parts) >= 3 else 0.0
    except ValueError:
        return 0.0


def _parse_axis_z(joint_element):
    """Return the z component of the joint ``<axis xyz="…">``, default 1.0."""
    axis = joint_element.find('axis')
    if axis is None:
        return 1.0
    parts = axis.get('xyz', '0 0 1').split()
    try:
        return float(parts[2]) if len(parts) >= 3 else 1.0
    except ValueError:
        return 1.0


def _load_urdf_root():
    """Process xacro and return the ElementTree root."""
    doc = xacro.process_file(os.path.abspath(XACRO_PATH))
    return ET.fromstring(doc.toxml())


def _build_world_z(urdf_root):
    """
    Return dict mapping link name -> world-frame z at spawn configuration.

    Spawn configuration: every prismatic joint at its lower limit, all others
    at their ``<origin>`` z offset only.
    """
    child_to_parent = {}
    for joint in urdf_root.findall('joint'):
        child_name = joint.find('child').get('link')
        parent_name = joint.find('parent').get('link')
        origin_z = _parse_origin_z(joint.find('origin'))

        extra_z = 0.0
        if joint.get('type') == 'prismatic':
            axis_z = _parse_axis_z(joint)
            limit = joint.find('limit')
            lower = float(limit.get('lower', '0')) if limit is not None else 0.
            extra_z = axis_z * lower

        child_to_parent[child_name] = (parent_name, origin_z + extra_z)

    all_links = {lnk.get('name') for lnk in urdf_root.findall('link')}
    all_children = set(child_to_parent.keys())
    root_links = all_links - all_children
    assert len(root_links) == 1, f'Expected one root link, got {root_links}'
    root_link = root_links.pop()

    world_z = {root_link: 0.0}
    parent_to_children = {}
    for child, (parent, dz) in child_to_parent.items():
        parent_to_children.setdefault(parent, []).append((child, dz))

    queue = [root_link]
    while queue:
        link = queue.pop(0)
        for child, dz in parent_to_children.get(link, []):
            world_z[child] = world_z[link] + dz
            queue.append(child)

    return world_z


def _geometry_half_z_extent(geom_element):
    """
    Return the z half-extent of a ``<geometry>`` child element.

    Returns None for ``<mesh>`` — no lightweight bound available.
    """
    box = geom_element.find('box')
    if box is not None:
        size = box.get('size', '0 0 0').split()
        return float(size[2]) / 2.0 if len(size) >= 3 else 0.0

    cylinder = geom_element.find('cylinder')
    if cylinder is not None:
        return float(cylinder.get('length', '0')) / 2.0

    sphere = geom_element.find('sphere')
    if sphere is not None:
        return float(sphere.get('radius', '0'))

    return None


# ── test cases ───────────────────────────────────────────────────────────────

def test_g1_no_collision_below_ground():
    """T-G1: no collision geometry z-extent below GROUND_TOLERANCE at spawn."""
    urdf_root = _load_urdf_root()
    world_z = _build_world_z(urdf_root)

    violations = []
    for link in urdf_root.findall('link'):
        name = link.get('name')
        link_z = world_z.get(name, 0.0)

        for collision in link.findall('collision'):
            col_origin_z = _parse_origin_z(collision.find('origin'))
            col_z = link_z + col_origin_z

            geom = collision.find('geometry')
            if geom is None:
                continue
            half = _geometry_half_z_extent(geom)
            if half is None:
                continue

            lowest_z = col_z - half
            if lowest_z < GROUND_TOLERANCE:
                violations.append(
                    f'  {name}: lowest collision z = {lowest_z:.4f} m '
                    f'(link_z={link_z:.4f}, col_origin_z={col_origin_z:.4f}, '
                    f'half_extent={half:.4f})'
                )

    assert not violations, (
        'Collision geometry intersects ground plane below GROUND_TOLERANCE '
        f'({GROUND_TOLERANCE} m) at spawn.\n'
        'This causes Gazebo DARTsim impulses that destabilise rover physics.\n'
        'Options: raise link origin, remove <collision>, or add <dynamics> '
        'friction (if geometry is nominally above ground but could drift).\n\n'
        + '\n'.join(violations)
    )


def test_g2_joint_parents_exist():
    """T-G2: every joint's parent link is defined in the URDF."""
    urdf_root = _load_urdf_root()
    defined_links = {lnk.get('name') for lnk in urdf_root.findall('link')}
    missing = []
    for joint in urdf_root.findall('joint'):
        parent = joint.find('parent').get('link')
        if parent not in defined_links:
            missing.append(
                f"  joint '{joint.get('name')}' parent '{parent}' not defined"
            )
    assert not missing, 'Undefined parent links:\n' + '\n'.join(missing)


def test_g3_prismatic_lower_limit_non_negative_for_downward_axis():
    """T-G3: prismatic joints with downward axis must have lower >= 0."""
    urdf_root = _load_urdf_root()
    world_z = _build_world_z(urdf_root)
    violations = []

    for joint in urdf_root.findall('joint'):
        if joint.get('type') != 'prismatic':
            continue
        axis_z = _parse_axis_z(joint)
        if axis_z >= 0:
            continue

        limit = joint.find('limit')
        lower = float(limit.get('lower', '0')) if limit is not None else 0.0
        if lower < 0:
            parent_name = joint.find('parent').get('link')
            parent_z = world_z.get(parent_name, 0.0)
            violations.append(
                f"  joint '{joint.get('name')}' axis_z={axis_z} lower={lower} "
                f'(parent world_z={parent_z:.4f}) — child could descend '
                f'{abs(axis_z * lower):.4f} m below its rest position'
            )

    assert not violations, (
        'Prismatic joints with downward axis have negative lower limits:\n'
        + '\n'.join(violations)
    )


def test_g4_link_world_z_tree_is_complete():
    """T-G4: every link in the URDF is reachable from the root (no orphans)."""
    urdf_root = _load_urdf_root()
    world_z = _build_world_z(urdf_root)
    all_links = {lnk.get('name') for lnk in urdf_root.findall('link')}
    orphans = all_links - set(world_z.keys())
    assert not orphans, f'Orphan links (not reachable from root): {orphans}'


def test_g1_detects_violation_on_synthetic_urdf():
    """Meta-test: T-G1 correctly flags a synthetic underground collision."""
    bad_urdf = """<?xml version="1.0"?>
<robot name="test_robot">
  <link name="base_footprint"/>
  <joint name="j" type="fixed">
    <parent link="base_footprint"/>
    <child link="bad_link"/>
    <origin xyz="0 0 -0.5"/>
  </joint>
  <link name="bad_link">
    <collision>
      <origin xyz="0 0 0"/>
      <geometry><box size="0.1 0.1 0.1"/></geometry>
    </collision>
    <inertial>
      <mass value="0.1"/>
      <inertia ixx="0.001" ixy="0" ixz="0" iyy="0.001" iyz="0" izz="0.001"/>
    </inertial>
  </link>
</robot>"""
    urdf_root = ET.fromstring(bad_urdf)
    world_z = _build_world_z(urdf_root)
    assert world_z['bad_link'] == pytest.approx(-0.5)

    violations = []
    for link in urdf_root.findall('link'):
        name = link.get('name')
        link_z = world_z.get(name, 0.0)
        for collision in link.findall('collision'):
            col_z = link_z + _parse_origin_z(collision.find('origin'))
            geom = collision.find('geometry')
            half = _geometry_half_z_extent(geom)
            if half is not None and (col_z - half) < GROUND_TOLERANCE:
                violations.append(name)
    assert 'bad_link' in violations, 'Meta-test: violation not detected'
