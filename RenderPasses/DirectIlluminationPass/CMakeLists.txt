add_plugin(DirectIlluminationPass)

target_sources(DirectIlluminationPass PRIVATE
    DirectIlluminationPass.cpp
    DirectIlluminationPass.h
    DirectIlluminationPass.3d.slang
)

target_copy_shaders(DirectIlluminationPass RenderPasses/DirectIlluminationPass)

target_source_group(DirectIlluminationPass "RenderPasses")
