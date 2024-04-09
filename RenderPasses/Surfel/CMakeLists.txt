add_plugin(Surfel)

target_sources(Surfel PRIVATE
    SurfelBase.cpp

    HashUtils.hlsli
    Random.hlsli
    SurfelTypes.hlsli
    SurfelUtils.hlsli

    SurfelGBuffer/SurfelGBuffer.cpp
    SurfelGBuffer/SurfelGBuffer.h
    SurfelGBuffer/SurfelGBuffer.3d.slang

    SurfelPreparePass/SurfelPreparePass.cpp
    SurfelPreparePass/SurfelPreparePass.h
    SurfelPreparePass/SurfelPreparePass.hlsl

    SurfelUpdatePass/SurfelUpdatePass.cpp
    SurfelUpdatePass/SurfelUpdatePass.h
    SurfelUpdatePass/SurfelUpdatePass.cs.slang

    SurfelCoveragePass/SurfelCoveragePass.cpp
    SurfelCoveragePass/SurfelCoveragePass.h
    SurfelCoveragePass/SurfelCoveragePass.hlsl

    SurfelGenPass/SurfelGenPass.cpp
    SurfelGenPass/SurfelGenPass.h
    SurfelGenPass/SurfelGenPass.cs.slang

    SurfelDebugPass/SurfelDebugPass.cpp
    SurfelDebugPass/SurfelDebugPass.h
    SurfelDebugPass/SurfelDebugPass.3d.slang
)

target_copy_shaders(Surfel RenderPasses/Surfel)

target_source_group(Surfel "RenderPasses")
