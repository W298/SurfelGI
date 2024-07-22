add_plugin(Surfel)

target_sources(Surfel PRIVATE
    Surfel.cpp

    HashUtils.slang
    Random.slang

    SurfelGBuffer/SurfelGBuffer.cpp
    SurfelGBuffer/SurfelGBuffer.h
    SurfelGBuffer/SurfelGBuffer.3d.slang

    SurfelVBuffer/SurfelVBuffer.cpp
    SurfelVBuffer/SurfelVBuffer.h
    SurfelVBuffer/SurfelVBuffer.rt.slang

    SurfelDirectLightingPass/SurfelDirectLightingPass.cpp
    SurfelDirectLightingPass/SurfelDirectLightingPass.h
    SurfelDirectLightingPass/SurfelDirectLightingPass.cs.slang

    SurfelGI/StaticParams.slang
    SurfelGI/OverlayMode.slang
    SurfelGI/SurfelGI.cpp
    SurfelGI/SurfelGI.h
    SurfelGI/SurfelTypes.slang
    SurfelGI/SurfelUtils.slang
    SurfelGI/SurfelPreparePass.cs.slang
    SurfelGI/SurfelUpdatePass.cs.slang
    SurfelGI/SurfelRayTrace.rt.slang
    SurfelGI/SurfelGenerationPass.cs.slang
    SurfelGI/SurfelIntegratePass.cs.slang
    SurfelGI/SurfelEvaluationPass.cs.slang
    SurfelGI/MultiscaleMeanEstimator.slang
)

target_copy_shaders(Surfel RenderPasses/Surfel)

target_source_group(Surfel "RenderPasses")
