#include "SurfelDebugPass.h"

SurfelDebugPass::SurfelDebugPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");
}

RenderPassReflection SurfelDebugPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    // Input
    reflector.addInput("instanceIDVisual", "Instance ID Visualization")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput("surfel", "surfel texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::ShaderResource);

    // Output
    reflector.addOutput("debug", "debug texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    return reflector;
}

void SurfelDebugPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pInstanceIDVisual = renderData.getTexture("instanceIDVisual");
    const auto& pSurfel = renderData.getTexture("surfel");
   
    const auto& pDebug = renderData.getTexture("debug");

    FALCOR_ASSERT(pInstanceIDVisual && pSurfel && pDebug);

    const uint2 resolution = uint2(pInstanceIDVisual->getWidth(), pInstanceIDVisual->getHeight());

    if (mpComputePass)
    {
        auto var = mpComputePass->getRootVar();

        var["gInstanceIDVisual"] = pInstanceIDVisual;
        var["gSurfel"] = pSurfel;

        var["gDebug"] = pDebug;

        pRenderContext->clearUAV(pDebug->getUAV().get(), float4(0));
        mpComputePass->execute(pRenderContext, uint3(resolution, 1));
    }

    mFrameIndex++;
}

void SurfelDebugPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        mpComputePass = ComputePass::create(
            mpDevice,
            "RenderPasses/Surfel/SurfelDebugPass/SurfelDebugPass.cs.slang",
            "csMain",
            mpScene->getSceneDefines()
        );
    }
}
