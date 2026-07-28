"""Blender addon entry point for native Granny2 support."""

bl_info = {
    "name": "Granny2 Native (.gr2)",
    "author": "ciupix + Codex",
    "version": (0, 1, 43),
    "blender": (3, 6, 0),
    "location": "File > Import-Export",
    "description": "Import and export Granny2 .gr2 files with native parsers",
    "category": "Import-Export",
}


def _load_bpy():
    try:
        import bpy  # type: ignore
        from bpy_extras.io_utils import ExportHelper, ImportHelper  # type: ignore
        from pathlib import Path
        from bpy.props import BoolProperty, FloatProperty, IntProperty, StringProperty  # type: ignore
    except Exception:
        return None, None, None, None, None, None, None, None
    return bpy, ExportHelper, ImportHelper, Path, BoolProperty, FloatProperty, IntProperty, StringProperty


bpy, ExportHelper, ImportHelper, Path, BoolProperty, FloatProperty, IntProperty, StringProperty = _load_bpy()


if bpy is not None:

    class IMPORT_SCENE_OT_gr2_native(bpy.types.Operator, ImportHelper):
        bl_idname = "import_scene.gr2_native"
        bl_label = "Import Granny2 (.gr2)"
        bl_options = {"REGISTER", "UNDO"}

        filename_ext = ".gr2"
        filter_glob: StringProperty(default="*.gr2;*.GR2", options={"HIDDEN"})
        scale: FloatProperty(
            name="Scale",
            description="Scale imported vertex positions",
            default=1.0,
            min=0.0001,
            max=10000.0,
        )
        max_meshes: IntProperty(
            name="Max Meshes",
            description="Maximum mesh objects to import",
            default=64,
            min=1,
            max=4096,
        )
        import_uvs: BoolProperty(
            name="Import UVs",
            description="Create UV layer when texture coordinates exist",
            default=True,
        )
        flip_uv_v: BoolProperty(
            name="Flip UV V",
            description="Flip texture V coordinates from Granny image space into Blender UV space",
            default=True,
        )
        import_vertices_without_faces: BoolProperty(
            name="Import Vertex-Only Meshes",
            description="Import meshes even when topology indices are absent",
            default=True,
        )
        import_vertex_groups: BoolProperty(
            name="Import Vertex Groups",
            description="Create vertex groups from Granny mesh bone bindings and weights",
            default=True,
        )
        import_armatures: BoolProperty(
            name="Import Armatures",
            description="Create Blender armatures from Granny skeletons",
            default=True,
        )
        import_animations: BoolProperty(
            name="Import Animations",
            description="Create Blender actions from Granny animation metadata",
            default=True,
        )
        shade_smooth: BoolProperty(
            name="Shade Smooth",
            description="Use smooth polygon shading on imported meshes",
            default=True,
        )
        animation_filepath: StringProperty(
            name="Animation GR2",
            description="Optional separate .gr2 animation file to apply to the imported armature",
            default="",
            subtype="FILE_PATH",
        )
        load_textures: BoolProperty(
            name="Load Textures",
            description="Resolve texture file paths and connect image nodes when files exist",
            default=True,
        )
        texture_search_roots: StringProperty(
            name="Texture Search Roots",
            description="Extra texture search roots separated by semicolons",
            default="",
        )

        def execute(self, context):
            from .gr2.file import read_gr2
            from .gr2.fixup import load_sections
            from .gr2.geometry import extract_mesh_geometries
            from .gr2.skeleton import extract_skeletons
            from .gr2.animation import extract_animation_set
            from .gr2.decompress import DecompressionError

            gr2_file = read_gr2(self.filepath)
            try:
                loaded = load_sections(gr2_file)
                geometries = extract_mesh_geometries(loaded, max_meshes=self.max_meshes)
                skeletons = extract_skeletons(loaded) if self.import_armatures else ()
                animation_loaded = loaded
                if self.import_animations and self.animation_filepath:
                    animation_loaded = load_sections(read_gr2(self.animation_filepath))
                animation_set = extract_animation_set(animation_loaded) if self.import_animations else None
            except DecompressionError as exc:
                self.report({"ERROR"}, str(exc))
                return {"CANCELLED"}

            collection = context.collection
            armatures = [
                _create_armature_object(context, collection, skeleton, self.scale)
                for skeleton in skeletons
                if skeleton.bones
            ]
            if animation_set is not None:
                _create_animation_actions(animation_set, armatures, context.scene)
            texture_roots = _parse_texture_roots(self.texture_search_roots)
            made = 0
            for geometry in geometries:
                if not geometry.triangles and not self.import_vertices_without_faces:
                    continue
                vertices = [
                    (
                        position[0] * self.scale,
                        position[1] * self.scale,
                        position[2] * self.scale,
                    )
                    for position in geometry.positions
                ]
                mesh = bpy.data.meshes.new(geometry.name)
                mesh.from_pydata(vertices, [], list(geometry.triangles))
                for material in geometry.materials:
                    mesh.materials.append(
                        _create_blender_material(
                            material,
                            gr2_file.path,
                            texture_roots,
                            load_textures=self.load_textures,
                        )
                    )
                for group in geometry.triangle_groups:
                    if group.material_index < 0 or group.material_index >= len(mesh.materials):
                        continue
                    start = max(group.tri_first, 0)
                    end = min(start + max(group.tri_count, 0), len(mesh.polygons))
                    for polygon in mesh.polygons[start:end]:
                        polygon.material_index = group.material_index
                mesh.update()
                if self.shade_smooth:
                    for polygon in mesh.polygons:
                        polygon.use_smooth = True
                    mesh.update()
                if self.import_uvs and geometry.uvs and mesh.polygons:
                    uv_layer = mesh.uv_layers.new(name="UVMap")
                    for polygon in mesh.polygons:
                        for loop_index in polygon.loop_indices:
                            vertex_index = mesh.loops[loop_index].vertex_index
                            if vertex_index < len(geometry.uvs):
                                u, v = geometry.uvs[vertex_index]
                                uv_layer.data[loop_index].uv = (u, 1.0 - v) if self.flip_uv_v else (u, v)
                obj = bpy.data.objects.new(geometry.name, mesh)
                obj["gr2_source"] = str(gr2_file.path)
                obj["gr2_vertex_count"] = geometry.vertex_count
                obj["gr2_index_count"] = geometry.index_count
                obj["gr2_vertex_stride"] = geometry.vertex_stride
                obj["gr2_components"] = ",".join(component.name for component in geometry.components)
                obj["gr2_bone_bindings"] = ",".join(binding.name for binding in geometry.bone_bindings)
                if self.import_vertex_groups:
                    groups = [
                        obj.vertex_groups.new(name=binding.name)
                        for binding in geometry.bone_bindings
                    ]
                    for vertex_index, weights in enumerate(geometry.vertex_weights):
                        for item in weights:
                            if item.bone_index < len(groups):
                                groups[item.bone_index].add([vertex_index], item.weight, "ADD")
                armature = _matching_armature(geometry, armatures)
                if armature is not None:
                    modifier = obj.modifiers.new(name="GR2 Armature", type="ARMATURE")
                    modifier.object = armature
                collection.objects.link(obj)
                made += 1

            self.report(
                {"INFO"},
                f"Imported {made} meshes from {gr2_file.path.name}",
            )
            return {"FINISHED"}


    def menu_func_import(self, context):
        self.layout.operator(IMPORT_SCENE_OT_gr2_native.bl_idname, text="Granny2 (.gr2)")


    class EXPORT_SCENE_OT_gr2_native(bpy.types.Operator, ExportHelper):
        bl_idname = "export_scene.gr2_native"
        bl_label = "Export Granny2 Raw (.gr2 WIP)"
        bl_options = {"REGISTER"}

        filename_ext = ".gr2"
        filter_glob: StringProperty(default="*.gr2;*.GR2", options={"HIDDEN"})
        selected_only: BoolProperty(
            name="Selected Only",
            description="Export selected meshes and referenced armatures",
            default=True,
        )
        apply_modifiers: BoolProperty(
            name="Apply Modifiers",
            description="Collect evaluated mesh data before raw GR2 writing",
            default=False,
        )
        scale: FloatProperty(
            name="Scale",
            description="Scale exported vertex positions",
            default=1.0,
            min=0.0001,
            max=10000.0,
        )
        flip_uv_v: BoolProperty(
            name="Flip UV V",
            description="Convert Blender UV V back to Granny image-space V",
            default=True,
        )

        def execute(self, context):
            from .gr2.export import collect_export_scene, write_export_manifest
            from .gr2.write import write_raw_gr2

            scene = collect_export_scene(
                context,
                selected_only=self.selected_only,
                apply_modifiers=self.apply_modifiers,
                scale=self.scale,
                flip_uv_v=self.flip_uv_v,
            )
            if not scene.meshes:
                self.report({"ERROR"}, "No mesh objects available for GR2 export")
                return {"CANCELLED"}

            try:
                write_raw_gr2(self.filepath, scene)
            except ValueError as exc:
                self.report({"ERROR"}, str(exc))
                return {"CANCELLED"}
            manifest_path = Path(self.filepath).with_suffix(Path(self.filepath).suffix + ".export.json")
            write_export_manifest(manifest_path, scene)
            self.report(
                {"INFO"},
                (
                    f"Exported raw GR2: {scene.mesh_count} meshes, {scene.skeleton_count} skeletons, "
                    f"{scene.vertex_count} vertices, {scene.triangle_count} triangles"
                ),
            )
            return {"FINISHED"}


    def menu_func_export(self, context):
        self.layout.operator(EXPORT_SCENE_OT_gr2_native.bl_idname, text="Granny2 Raw WIP (.gr2)")


    def _create_armature_object(context, collection, skeleton, scale):
        from mathutils import Matrix, Quaternion, Vector  # type: ignore

        armature_data = bpy.data.armatures.new(skeleton.name)
        armature_data.display_type = "STICK"
        armature_obj = bpy.data.objects.new(skeleton.name, armature_data)
        collection.objects.link(armature_obj)

        previous_active = context.view_layer.objects.active
        previous_selected = [obj for obj in context.view_layer.objects if obj.select_get()]
        for obj in previous_selected:
            obj.select_set(False)
        armature_obj.select_set(True)
        context.view_layer.objects.active = armature_obj
        bpy.ops.object.mode_set(mode="EDIT")

        world_matrices = _bone_world_matrices(skeleton, Matrix, Quaternion, Vector, scale)
        child_map = _bone_child_map(skeleton)
        edit_bones = {}
        for bone in skeleton.bones:
            matrix = world_matrices[bone.index]
            head = matrix.translation
            tail = _bone_tail(skeleton, bone.index, world_matrices, child_map, Vector, scale)
            edit_bone = armature_data.edit_bones.new(bone.name)
            edit_bone.head = head
            edit_bone.tail = tail
            edit_bones[bone.index] = edit_bone

        for bone in skeleton.bones:
            if bone.parent_index in edit_bones and bone.index in edit_bones:
                edit_bones[bone.index].parent = edit_bones[bone.parent_index]
        for bone in skeleton.bones:
            edit_bone = edit_bones.get(bone.index)
            if edit_bone is None:
                continue
            roll_axis = world_matrices[bone.index].to_quaternion() @ Vector((0.0, 0.0, 1.0))
            if roll_axis.length > 0.0001:
                edit_bone.align_roll(roll_axis.normalized())

        bpy.ops.object.mode_set(mode="OBJECT")
        for bone in skeleton.bones:
            pose_bone = armature_obj.pose.bones.get(bone.name)
            data_bone = armature_data.bones.get(bone.name)
            if pose_bone is not None:
                pose_bone["gr2_transform_flags"] = bone.transform.flags
                pose_bone["gr2_local_position"] = tuple(bone.transform.position)
                pose_bone["gr2_local_orientation_xyzw"] = tuple(bone.transform.orientation)
            if data_bone is not None and bone.inverse_world_transform:
                data_bone["gr2_inverse_world_transform"] = tuple(bone.inverse_world_transform)
            if data_bone is not None and bone.index < len(world_matrices):
                granny_local = _granny_local_matrix(bone, world_matrices)
                blender_local = _bone_rest_local_matrix(data_bone)
                data_bone["gr2_granny_rest_local"] = _matrix_to_tuple(granny_local)
                data_bone["gr2_axis_remap"] = _matrix_to_tuple(granny_local.inverted() @ blender_local)
        armature_obj.select_set(False)
        for obj in previous_selected:
            obj.select_set(True)
        context.view_layer.objects.active = previous_active
        armature_obj["gr2_bone_count"] = len(skeleton.bones)
        armature_obj["gr2_lod_type"] = skeleton.lod_type
        return armature_obj


    def _create_animation_actions(animation_set, armatures, scene=None):
        if not animation_set.animations:
            return
        armature_by_name = {armature.name: armature for armature in armatures}
        track_group_by_name = {track_group.name: track_group for track_group in animation_set.track_groups}
        fallback = armatures[0] if armatures else None
        max_frame = 1
        best_time_step = 0.0
        for animation in animation_set.animations:
            frame_count = max(1, int(round(animation.duration / animation.time_step))) if animation.time_step > 0 else 1
            max_frame = max(max_frame, frame_count + 1)
            if animation.time_step > 0:
                best_time_step = animation.time_step
            targets = [
                (name, armature_by_name[name])
                for name in animation.track_group_names
                if name in armature_by_name
            ]
            if not targets and fallback is not None:
                fallback_name = animation.track_group_names[0] if animation.track_group_names else fallback.name
                targets = [(fallback_name, fallback)]
            for track_group_name, target in targets:
                suffix = "" if len(targets) == 1 else f" ({track_group_name})"
                action = bpy.data.actions.new(_action_name(animation.name) + suffix)
                action.frame_range = (1.0, float(frame_count + 1))
                action["gr2_duration"] = animation.duration
                action["gr2_time_step"] = animation.time_step
                action["gr2_oversampling"] = animation.oversampling
                action["gr2_track_groups"] = track_group_name
                target.animation_data_create()
                target.animation_data.action = action
                scoped_track_groups = (
                    {track_group_name: track_group_by_name[track_group_name]}
                    if track_group_name in track_group_by_name
                    else track_group_by_name
                )
                keyed_bones = _insert_static_pose_keys(
                    action,
                    target,
                    animation,
                    scoped_track_groups,
                    float(frame_count + 1),
                )
                action["gr2_static_keyed_bones"] = keyed_bones
        if scene is not None and max_frame > 1:
            scene.frame_start = 1
            scene.frame_end = max_frame
            scene.frame_set(1)
            if best_time_step > 0:
                fps = max(1, min(240, int(round(1.0 / best_time_step))))
                scene.render.fps = fps


    def _insert_static_pose_keys(action, armature, animation, track_group_by_name, end_frame):
        keyed_bones = set()
        for track_group_name in animation.track_group_names:
            track_group = track_group_by_name.get(track_group_name)
            if track_group is None:
                continue
            for track in track_group.transform_tracks:
                pose_bone = armature.pose.bones.get(track.name)
                if pose_bone is None:
                    continue
                frames, locations, rotations = _track_pose_basis_samples(
                    armature,
                    track,
                    animation.duration,
                    animation.time_step,
                    end_frame,
                )
                if not frames:
                    continue
                if locations:
                    data_path = _bone_data_path(track.name, "location")
                    for axis in range(3):
                        _add_keyed_fcurve(action, armature, data_path, axis, frames, [value[axis] for value in locations])
                if rotations:
                    pose_bone.rotation_mode = "QUATERNION"
                    data_path = _bone_data_path(track.name, "rotation_quaternion")
                    for axis in range(4):
                        _add_keyed_fcurve(action, armature, data_path, axis, frames, [value[axis] for value in rotations])
                keyed_bones.add(track.name)
        return len(keyed_bones)


    def _track_pose_basis_samples(armature, track, duration, time_step, end_frame):
        from .gr2.animation import sample_curve_values

        count = 0
        position_values = []
        orientation_values = []
        if track.position is not None:
            if track.position.control_values:
                _, position_values = sample_curve_values(track.position, duration, time_step)
            elif len(track.position.sample_value) >= 3:
                position_values = [track.position.sample_value[:3], track.position.sample_value[:3]]
            count = max(count, len(position_values))
        if track.orientation is not None:
            if track.orientation.control_values:
                _, orientation_values = sample_curve_values(track.orientation, duration, time_step)
            elif len(track.orientation.sample_value) >= 4:
                orientation_values = [track.orientation.sample_value[:4], track.orientation.sample_value[:4]]
            count = max(count, len(orientation_values))
        if count <= 0:
            return (), (), ()

        rest_position, rest_orientation = _rest_local_transform(armature, track.name)
        positions = _expand_samples(position_values, count, rest_position)
        orientations = _expand_samples(orientation_values, count, rest_orientation)
        frames = _sample_frames(count) if count > 2 else (1.0, end_frame)
        locations = []
        rotations = []
        for position, orientation in zip(positions, orientations):
            location, rotation = _to_pose_basis_transform(armature, track.name, position, orientation)
            locations.append(location)
            rotations.append(rotation)
        return frames, locations, rotations


    def _expand_samples(values, count, fallback):
        if not values:
            return [fallback] * count
        if len(values) >= count:
            return list(values[:count])
        return list(values) + [values[-1]] * (count - len(values))


    def _rest_local_transform(armature, bone_name):
        matrix = _granny_rest_local_matrix(armature, bone_name)
        if matrix is None:
            return (0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0)
        quat = matrix.to_quaternion()
        return tuple(matrix.translation), (quat.x, quat.y, quat.z, quat.w)


    def _to_pose_basis_transform(armature, bone_name, position, orientation):
        from mathutils import Matrix, Quaternion, Vector  # type: ignore

        rest = _granny_rest_local_matrix(armature, bone_name)
        remap = _axis_remap_matrix(armature, bone_name)
        if rest is None:
            x, y, z, w = orientation[:4]
            return tuple(position[:3]), (w, x, y, z)
        x, y, z, w = orientation[:4]
        local = Matrix.Translation(Vector(position[:3])) @ Quaternion((w, x, y, z)).to_matrix().to_4x4()
        basis = rest.inverted() @ local
        if remap is not None:
            basis = remap.inverted() @ basis @ remap
        rotation = basis.to_quaternion()
        return tuple(basis.translation), (rotation.w, rotation.x, rotation.y, rotation.z)


    def _granny_rest_local_matrix(armature, bone_name):
        bone = armature.data.bones.get(bone_name)
        if bone is None:
            return None
        return _matrix_from_tuple(bone.get("gr2_granny_rest_local"))


    def _axis_remap_matrix(armature, bone_name):
        bone = armature.data.bones.get(bone_name)
        if bone is None:
            return None
        return _matrix_from_tuple(bone.get("gr2_axis_remap"))


    def _bone_rest_local_matrix(bone):
        if bone.parent is None:
            return bone.matrix_local.copy()
        return bone.parent.matrix_local.inverted() @ bone.matrix_local


    def _granny_local_matrix(bone, world_matrices):
        matrix = world_matrices[bone.index].copy()
        if 0 <= bone.parent_index < len(world_matrices):
            return world_matrices[bone.parent_index].inverted() @ matrix
        return matrix


    def _matrix_to_tuple(matrix):
        return tuple(float(matrix[row][column]) for row in range(4) for column in range(4))


    def _matrix_from_tuple(values):
        if values is None or len(values) != 16:
            return None
        from mathutils import Matrix  # type: ignore

        return Matrix(
            (
                values[0:4],
                values[4:8],
                values[8:12],
                values[12:16],
            )
        )


    def _rest_local_matrix(armature, bone_name):
        bone = armature.data.bones.get(bone_name)
        if bone is None:
            return None
        if bone.parent is None:
            return bone.matrix_local.copy()
        return bone.parent.matrix_local.inverted() @ bone.matrix_local


    def _sample_frames(sample_count):
        return [float(index + 1) for index in range(sample_count)]


    def _add_static_fcurve(action, armature, data_path, array_index, frames, value):
        _add_keyed_fcurve(action, armature, data_path, array_index, frames, [value] * len(frames))


    def _add_keyed_fcurve(action, armature, data_path, array_index, frames, values):
        if not frames or not values:
            return
        fcurve = _new_action_fcurve(action, armature, data_path, array_index)
        fcurve.keyframe_points.add(len(frames))
        for point, frame, value in zip(fcurve.keyframe_points, frames, values):
            point.co = (frame, value)
            point.interpolation = "LINEAR"
        fcurve.extrapolation = "CONSTANT"
        fcurve.update()


    def _new_action_fcurve(action, armature, data_path, array_index):
        if hasattr(action, "fcurves"):
            return action.fcurves.new(data_path=data_path, index=array_index)
        return action.fcurve_ensure_for_datablock(armature, data_path, index=array_index)


    def _bone_data_path(bone_name, prop):
        escaped = bone_name.replace("\\", "\\\\").replace('"', '\\"')
        return f'pose.bones["{escaped}"].{prop}'


    def _action_name(name):
        text = str(name or "GR2 Action").replace("\\", "/").rstrip("/")
        return text.rsplit("/", 1)[-1] or "GR2 Action"


    def _bone_world_matrices(skeleton, Matrix, Quaternion, Vector, scale):
        inverse_world_matrices = _bone_inverse_world_matrices(skeleton, Matrix, Vector, scale)
        if inverse_world_matrices is not None:
            return inverse_world_matrices
        matrices = []
        for bone in skeleton.bones:
            x, y, z, w = bone.transform.orientation
            local = Matrix.Translation(Vector(bone.transform.position) * scale) @ Quaternion((w, x, y, z)).to_matrix().to_4x4()
            if 0 <= bone.parent_index < len(matrices):
                matrices.append(matrices[bone.parent_index] @ local)
            else:
                matrices.append(local)
        return matrices


    def _bone_inverse_world_matrices(skeleton, Matrix, Vector, scale):
        matrices = []
        for bone in skeleton.bones:
            values = bone.inverse_world_transform
            if len(values) != 16:
                return None
            try:
                inverse_world = Matrix(
                    (
                        values[0:4],
                        values[4:8],
                        values[8:12],
                        values[12:16],
                    )
                ).transposed()
                world = inverse_world.inverted()
            except Exception:
                return None
            world.translation = Vector(world.translation) * scale
            matrices.append(world)
        return matrices


    def _bone_child_map(skeleton):
        child_map = {bone.index: [] for bone in skeleton.bones}
        for bone in skeleton.bones:
            if bone.parent_index in child_map:
                child_map[bone.parent_index].append(bone.index)
        return child_map


    def _bone_tail(skeleton, bone_index, world_matrices, child_map, Vector, scale):
        head = world_matrices[bone_index].translation
        matrix_direction = world_matrices[bone_index].to_quaternion() @ Vector((0.0, 1.0, 0.0))
        if matrix_direction.length > 0.0001:
            length = _bone_display_length(skeleton, bone_index, world_matrices, child_map, scale)
            return head + matrix_direction.normalized() * length
        return head + Vector((0.0, max(0.25 * scale, 0.001), 0.0))


    def _bone_display_length(skeleton, bone_index, world_matrices, child_map, scale):
        head = world_matrices[bone_index].translation
        for child_index in child_map.get(bone_index, []):
            child_head = world_matrices[child_index].translation
            if (child_head - head).length > 0.0001:
                return max(min((child_head - head).length * 0.25, 6.0 * scale), 0.35 * scale)
        parent_index = skeleton.bones[bone_index].parent_index
        if 0 <= parent_index < len(world_matrices):
            direction = head - world_matrices[parent_index].translation
            if direction.length > 0.0001:
                return max(min(direction.length * 0.20, 4.0 * scale), 0.35 * scale)
        return max(0.35 * scale, 0.001)


    def _matching_armature(geometry, armatures):
        if not geometry.bone_bindings:
            return None
        binding_names = {binding.name for binding in geometry.bone_bindings}
        best = None
        best_count = 0
        for armature in armatures:
            bone_names = {bone.name for bone in armature.data.bones}
            count = len(binding_names & bone_names)
            if count > best_count:
                best = armature
                best_count = count
        return best if best_count else None


    def _create_blender_material(material, gr2_path, texture_roots, *, load_textures):
        from .gr2.texture import resolve_texture_path

        blend_material = bpy.data.materials.new(material.name or "GR2 Material")
        blend_material.diffuse_color = _material_color(material.index)
        blend_material["gr2_material_index"] = material.index
        if material.texture_file:
            blend_material["gr2_texture_file"] = material.texture_file
            resolved = resolve_texture_path(material.texture_file, Path(gr2_path), texture_roots)
            if resolved is not None:
                blend_material["gr2_texture_resolved"] = str(resolved)
                if load_textures:
                    _attach_image_texture(blend_material, resolved)
        if material.texture_size:
            blend_material["gr2_texture_width"] = material.texture_size[0]
            blend_material["gr2_texture_height"] = material.texture_size[1]
        return blend_material


    def _material_color(index):
        palette = (
            (0.72, 0.68, 0.60, 1.0),
            (0.56, 0.67, 0.82, 1.0),
            (0.70, 0.55, 0.50, 1.0),
            (0.48, 0.70, 0.58, 1.0),
            (0.78, 0.62, 0.38, 1.0),
            (0.62, 0.56, 0.76, 1.0),
        )
        return palette[index % len(palette)]


    def _attach_image_texture(material, image_path):
        material.use_nodes = True
        image = bpy.data.images.load(str(image_path), check_existing=True)
        nodes = material.node_tree.nodes
        links = material.node_tree.links
        image_node = nodes.new(type="ShaderNodeTexImage")
        image_node.image = image
        principled = nodes.get("Principled BSDF")
        if principled is not None:
            input_socket = principled.inputs.get("Base Color")
            if input_socket is not None:
                links.new(image_node.outputs["Color"], input_socket)


    def _parse_texture_roots(raw):
        roots = []
        for item in raw.split(";"):
            text = item.strip()
            if text:
                roots.append(Path(text).expanduser())
        return tuple(roots)


    def register():
        bpy.utils.register_class(IMPORT_SCENE_OT_gr2_native)
        bpy.utils.register_class(EXPORT_SCENE_OT_gr2_native)
        bpy.types.TOPBAR_MT_file_import.append(menu_func_import)
        bpy.types.TOPBAR_MT_file_export.append(menu_func_export)


    def unregister():
        bpy.types.TOPBAR_MT_file_export.remove(menu_func_export)
        bpy.types.TOPBAR_MT_file_import.remove(menu_func_import)
        bpy.utils.unregister_class(EXPORT_SCENE_OT_gr2_native)
        bpy.utils.unregister_class(IMPORT_SCENE_OT_gr2_native)

else:

    def register():
        return None


    def unregister():
        return None
