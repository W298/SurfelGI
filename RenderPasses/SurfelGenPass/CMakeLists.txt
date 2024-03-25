add_plugin(SurfelGenPass)

target_sources(SurfelGenPass PRIVATE
    SurfelGenPass.cpp
    SurfelGenPass.h
)

target_source_group(SurfelGenPass "RenderPasses")
