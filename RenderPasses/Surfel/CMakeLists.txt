add_plugin(Surfel)

target_sources(Surfel PRIVATE
    SurfelBase.cpp

    Random.slang
    SurfelTypes.slang
    SurfelUtil.slang

    SurfelPreparePass/SurfelPreparePass.cpp
    SurfelPreparePass/SurfelPreparePass.h
    SurfelPreparePass/SurfelPreparePass.cs.slang

    SurfelUpdatePass/SurfelUpdatePass.cpp
    SurfelUpdatePass/SurfelUpdatePass.h
    SurfelUpdatePass/SurfelUpdatePass.cs.slang

    SurfelGenPass/SurfelGenPass.cpp
    SurfelGenPass/SurfelGenPass.h
    SurfelGenPass/SurfelGenPass.cs.slang

    SurfelCoveragePass/SurfelCoveragePass.cpp
    SurfelCoveragePass/SurfelCoveragePass.h
    SurfelCoveragePass/SurfelCoveragePass.cs.slang
)

target_copy_shaders(Surfel RenderPasses/Surfel)

target_source_group(Surfel "RenderPasses")
