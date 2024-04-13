#include "SurfelPreparePass.h"
#include "../SurfelResource.h"

SurfelPreparePass::SurfelPreparePass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");

    mpComputePass =
        ComputePass::create(mpDevice, "RenderPasses/Surfel/SurfelPreparePass/SurfelPreparePass.hlsl", "csMain");
}

RenderPassReflection SurfelPreparePass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    // Empty

    return reflector;
}

void SurfelPreparePass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    auto& dict = renderData.getDictionary();

    getSurfelBuffer(mpDevice, dict);
    getSurfelFreeIndexBuffer(mpDevice, dict);
    getCellInfoBuffer(mpDevice, dict);
    getCellToSurfelBuffer(mpDevice, dict);

    getSurfelConfig(mpDevice, dict);

    if (mpComputePass)
    {
        auto var = mpComputePass->getRootVar();
        var[kSurfelCounterVarName] = getSurfelCounter(mpDevice, dict);

        mpComputePass->execute(pRenderContext, uint3(1));
        pRenderContext->copyResource(
            getSurfelDirtyIndexBuffer(mpDevice, dict).get(),
            getSurfelValidIndexBuffer(mpDevice, dict).get()
        );
    }
}
