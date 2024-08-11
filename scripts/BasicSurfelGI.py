from pathlib import WindowsPath, PosixPath
from falcor import *

def render_graph_DefaultRenderGraph():
    g = RenderGraph('DefaultRenderGraph')
    g.create_pass('ToneMapper', 'ToneMapper', {'outputSize': 'Default', 'useSceneMetadata': True, 'exposureCompensation': 0.0, 'autoExposure': False, 'filmSpeed': 100.0, 'whiteBalance': False, 'whitePoint': 6500.0, 'operator': 'HableUc2', 'clamp': True, 'whiteMaxLuminance': 1.0, 'whiteScale': 11.199999809265137, 'fNumber': 1.0, 'shutter': 1.0, 'exposureMode': 'AperturePriority'})
    g.create_pass('SurfelGI', 'SurfelGI', {})
    g.create_pass('SurfelGBuffer', 'SurfelGBuffer', {})
    g.create_pass('SurfelGIRenderPass', 'SurfelGIRenderPass', {})
    g.create_pass('SimplePostFX', 'SimplePostFX', {})
    g.add_edge('SurfelGBuffer.packedHitInfo', 'SurfelGI.packedHitInfo')
    g.add_edge('SurfelGBuffer.packedHitInfo', 'SurfelGIRenderPass.packedHitInfo')
    g.add_edge('SurfelGI.output', 'SurfelGIRenderPass.indirectLighting')
    g.add_edge('SurfelGIRenderPass.output', 'SimplePostFX.src')
    g.add_edge('SimplePostFX.dst', 'ToneMapper.src')
    g.mark_output('ToneMapper.dst')
    return g

DefaultRenderGraph = render_graph_DefaultRenderGraph()
try: m.addGraph(DefaultRenderGraph)
except NameError: None
