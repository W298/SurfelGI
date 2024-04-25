add_plugin(Surfel)

target_sources(Surfel PRIVATE
    SurfelBase.cpp
    SurfelResource.h

    HashUtils.slang
    Random.slang
    SurfelTypes.slang
    SurfelUtils.slang

    SurfelGBuffer/SurfelGBuffer.cpp
    SurfelGBuffer/SurfelGBuffer.h
    SurfelGBuffer/SurfelGBuffer.3d.slang

    SurfelPreparePass/SurfelPreparePass.cpp
    SurfelPreparePass/SurfelPreparePass.h
    SurfelPreparePass/SurfelPreparePass.cs.slang

    SurfelUpdatePass/SurfelUpdatePass.cpp
    SurfelUpdatePass/SurfelUpdatePass.h
    SurfelUpdatePass/SurfelUpdatePass.cs.slang

    SurfelCoveragePass/SurfelCoveragePass.cpp
    SurfelCoveragePass/SurfelCoveragePass.h
    SurfelCoveragePass/SurfelCoveragePass.cs.slang

    SurfelGenPass/SurfelGenPass.cpp
    SurfelGenPass/SurfelGenPass.h
    SurfelGenPass/SurfelGenPass.cs.slang

    SurfelDirectLightingPass/SurfelDirectLightingPass.cpp
    SurfelDirectLightingPass/SurfelDirectLightingPass.h
    SurfelDirectLightingPass/SurfelDirectLightingPass.cs.slang

    SurfelGI/SurfelGI.cpp
    SurfelGI/SurfelGI.h
    SurfelGI/SurfelPreparePass.cs.slang
    SurfelGI/SurfelUpdatePass.cs.slang
    SurfelGI/SurfelRayTrace.rt.slang
    SurfelGI/SurfelCoveragePass.cs.slang
    SurfelGI/SurfelGenPass.cs.slang
)

target_copy_shaders(Surfel RenderPasses/Surfel)

target_source_group(Surfel "RenderPasses")
