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

    SurfelGIRenderPass/SurfelGIRenderPass.cpp
    SurfelGIRenderPass/SurfelGIRenderPass.h
    SurfelGIRenderPass/LightingPass.cs.slang
    SurfelGIRenderPass/BlurringPass.cs.slang
    SurfelGIRenderPass/IntegratePass.cs.slang

    BilateralFilter/BilateralFilter.cpp
    BilateralFilter/BilateralFilter.h
    BilateralFilter/BilateralFilter.cs.slang

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
