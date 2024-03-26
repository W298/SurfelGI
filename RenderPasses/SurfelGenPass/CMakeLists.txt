add_plugin(SurfelGenPass)

target_sources(SurfelGenPass PRIVATE
    SurfelGenPass.cpp
    SurfelGenPass.h
    SurfelGenPass.cs.slang
)

target_copy_shaders(SurfelGenPass RenderPasses/SurfelGenPass)

target_source_group(SurfelGenPass "RenderPasses")
