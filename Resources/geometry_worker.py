"""Bundled, restricted scene renderer. Run in Blender; accepts JSON data, never code."""
import json
import math
import sys
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Vector

out = Path(sys.argv[sys.argv.index('--')+1])
spec = json.loads((out/'scene.json').read_text())
kind, size = spec['kind'], float(spec['size'])
assert kind in ('circle','square','sphere','cube') and np.isfinite(size) and 0.05 <= size <= 1000
assert set(spec) <= {'kind','size','yaw','pitch','unit','texture'}
is_round, is_3d = kind in ('circle','sphere'), kind in ('sphere','cube')
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'NONE'  # User's explicit units remain in the scene specification.
scene['geometry_spec'] = json.dumps(spec,sort_keys=True)
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.render.resolution_x = scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.view_settings.view_transform = 'Standard'

if kind == 'sphere':
    lon, lat = 96, 48
    theta = np.arange(lon)*2*np.pi/lon
    phi = np.arange(1,lat)*np.pi/lat
    rings = np.stack(np.broadcast_arrays(np.sin(phi[:,None])*np.cos(theta),
        np.sin(phi[:,None])*np.sin(theta),np.cos(phi[:,None])*np.ones_like(theta)),axis=-1)*size
    vertices = [[0,0,size]]+rings.reshape(-1,3).tolist()+[[0,0,-size]]
    faces = [[0,1+j,1+(j+1)%lon] for j in range(lon)]
    for i in range(lat-2):
        for j in range(lon):
            a,b = 1+i*lon+j,1+i*lon+(j+1)%lon
            faces.append([a,a+lon,b+lon,b])
    last = 1+(lat-2)*lon
    faces += [[last+j,len(vertices)-1,last+(j+1)%lon] for j in range(lon)]
elif kind == 'cube':
    vertices = (np.array([[-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],
                         [-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]])*size/2).tolist()
    faces = [[0,3,2,1],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7],[4,5,6,7]]
elif kind == 'circle':
    theta = np.arange(384)*2*np.pi/384
    vertices = np.column_stack([size*np.cos(theta),size*np.sin(theta),np.zeros_like(theta)]).tolist()
    faces = [list(range(len(vertices)))]
else:
    vertices = (np.array([[-1,-1,0],[1,-1,0],[1,1,0],[-1,1,0]])*size/2).tolist()
    faces = [[0,1,2,3]]

mesh = bpy.data.meshes.new(kind+' coordinates')
mesh.from_pydata(vertices,[],faces)
mesh.update()
obj = bpy.data.objects.new(kind,mesh)
scene.collection.objects.link(obj)
uv = mesh.uv_layers.new(name='Image mapping')
for face in mesh.polygons:
    for index, loop in enumerate(face.loop_indices):
        vertex = mesh.vertices[mesh.loops[loop].vertex_index].co
        if kind == 'cube': coord = [(0,0),(1,0),(1,1),(0,1)][index]
        elif kind == 'sphere':
            u = (math.atan2(vertex.y,vertex.x)/(2*math.pi))%1
            # The UV seam lives between the final longitude and longitude zero.
            if face.center.y < 0 and u < 0.01: u = 1
            coord = (u,1-math.acos(np.clip(vertex.z/size,-1,1))/math.pi)
        else:
            half = size if is_round else size/2
            coord = (vertex.x/(2*half)+0.5,vertex.y/(2*half)+0.5)
        uv.data[loop].uv = coord
if kind == 'sphere':
    for face in mesh.polygons: face.use_smooth = True

material = bpy.data.materials.new('Mathematical surface')
material.use_nodes = True
bsdf = material.node_tree.nodes['Principled BSDF']
bsdf.inputs['Roughness'].default_value = 0.38
bsdf.inputs['Base Color'].default_value = (0.02,0.12,0.65,1)
texture_path = out/'texture.png'
if texture_path.exists() or kind in ('cube','square'):
    if texture_path.exists(): image = bpy.data.images.load(str(texture_path))
    else:
        yy,xx = np.indices((512,512))
        colors = np.array([[250,213,101,255],[237,103,73,255]],dtype=np.float32)/255
        pixels = colors[((xx//128+yy//128)%2).astype(int)]
        image = bpy.data.images.new('Calculated grid',width=512,height=512)
        image.pixels.foreach_set(pixels.ravel())
    image.pack()
    node = material.node_tree.nodes.new('ShaderNodeTexImage')
    node.image = image
    node.interpolation = 'Linear' if texture_path.exists() else 'Closest'
    material.node_tree.links.new(node.outputs['Color'],bsdf.inputs['Base Color'])
mesh.materials.append(material)

world = bpy.data.worlds.new('Neutral studio'); scene.world = world; world.use_nodes = True
world.node_tree.nodes['Background'].inputs[0].default_value = (0.35,0.38,0.42,1)
world.node_tree.nodes['Background'].inputs[1].default_value = 0.35
dimension = 2*size if is_round else size
camdata = bpy.data.cameras.new('Measured view'); cam = bpy.data.objects.new('Camera',camdata)
scene.collection.objects.link(cam)
if is_3d:
    yaw, pitch = np.deg2rad([float(spec.get('yaw',-35)),float(spec.get('pitch',25))])
    assert -np.pi <= yaw <= np.pi and abs(pitch) <= np.deg2rad(80)
    cam.location = Vector((np.sin(yaw)*np.cos(pitch),-np.cos(yaw)*np.cos(pitch),np.sin(pitch)))*dimension*8
else: cam.location = (0,0,dimension*8)
cam.rotation_euler = (-cam.location).to_track_quat('-Z','Y').to_euler()
camdata.type = 'ORTHO'; camdata.ortho_scale = dimension*(1.9 if kind == 'cube' else 1.45)
camdata.clip_end = max(100,dimension*20); camdata.clip_start = dimension*0.001
scene.camera = cam
for name, pos, energy, light_size in [('Key',(3,-4,6),1400,4),('Fill',(-4,-2,2),700,5),('Rim',(2,4,5),1900,3)]:
    data = bpy.data.lights.new(name,'AREA'); data.energy = energy*(dimension/2)**2
    data.shape = 'DISK'; data.size = light_size*dimension/2
    light = bpy.data.objects.new(name,data); scene.collection.objects.link(light)
    light.location = Vector(pos)*dimension/2
    light.rotation_euler = (-light.location).to_track_quat('-Z','Y').to_euler()

bm = bmesh.new(); bm.from_mesh(mesh)
assert all(face.calc_area()>1e-12 for face in bm.faces)
expected = [dimension,dimension,dimension if is_3d else 0]
assert np.allclose(list(obj.dimensions),expected,rtol=1e-6,atol=1e-6)
measurements = {'radius':size,'diameter':2*size,'area':float(np.pi*size**2),'circumference':float(2*np.pi*size)} if kind=='circle' else (
    {'edge':size,'area':size**2,'perimeter':4*size} if kind=='square' else (
    {'radius':size,'diameter':2*size,'surface_area':float(4*np.pi*size**2),'volume':float(4*np.pi*size**3/3)} if kind=='sphere' else
    {'edge':size,'face_area':size**2,'surface_area':6*size**2,'volume':size**3}))
report = {'verified':True,'kind':kind,'measurements':measurements,'dimensions':list(obj.dimensions),
          'vertices':len(mesh.vertices),'faces':len(mesh.polygons),'numpy_version':np.__version__,
          'blender_version':bpy.app.version_string,'uv_layers':len(mesh.uv_layers),'texture_packed':any(image.packed_file for image in bpy.data.images),
          'scene_spec':spec,'render_engine':'Cycles CPU'}
if is_3d:
    assert all(edge.is_manifold for edge in bm.edges)
    volume = bm.calc_volume(signed=True)
    error = abs(volume-measurements['volume'])/measurements['volume']
    assert volume>0 and error<0.005
    report.update(manifold=True,mesh_volume=volume,volume_relative_error=error)
else:
    area = sum(face.calc_area() for face in bm.faces)
    assert abs(area-measurements['area'])/measurements['area']<0.005
    report.update(mesh_area=area)
bm.free()
# Sources are reopenable without external texture dependencies.
bpy.ops.wm.save_as_mainfile(filepath=str(out/'scene.blend'),compress=False)
scene.render.filepath = str(out/'render.png')
bpy.ops.render.render(write_still=True)
(out/'verification.json').write_text(json.dumps(report,indent=2))
