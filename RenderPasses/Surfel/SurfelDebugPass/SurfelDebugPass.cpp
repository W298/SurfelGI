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

    // Output
    reflector.addOutput("debug", "debug texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    return reflector;
}

void SurfelDebugPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pDebug = renderData.getTexture("debug");

    FALCOR_ASSERT(pDebug);

    if (mpComputePass)
    {
        auto var = mpComputePass->getRootVar();
        var["gDebug"] = pDebug;

        pRenderContext->clearUAV(pDebug->getUAV().get(), float4(0));
        mpComputePass->execute(pRenderContext, uint3(1920, 1080, 1));
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
