add_plugin(Surfel)

target_sources(Surfel PRIVATE
    SurfelBase.cpp
    SurfelBase.h

    SurfelTypes.slang
    SurfelUtil.slang

    SurfelGenPass/SurfelGenPass.cpp
    SurfelGenPass/SurfelGenPass.h
    SurfelGenPass/SurfelGenPass.cs.slang

    SurfelCoveragePass/SurfelCoveragePass.cpp
    SurfelCoveragePass/SurfelCoveragePass.h
    SurfelCoveragePass/SurfelCoveragePass.cs.slang
)

target_copy_shaders(Surfel RenderPasses/Surfel)

target_source_group(Surfel "RenderPasses")
