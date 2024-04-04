#include "SurfelUpdatePass.h"

SurfelUpdatePass::SurfelUpdatePass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");
}

RenderPassReflection SurfelUpdatePass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    // Empty

    return reflector;
}

void SurfelUpdatePass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    auto& dict = renderData.getDictionary();

    if (mpCollectCellInfoPass)
    {
        auto var = mpCollectCellInfoPass->getRootVar();

        var["CB"]["gCameraPos"] = mpScene->getCamera()->getPosition();

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");
        var["gSurfelStatus"] = dict.getValue<ref<Buffer>>("surfelStatus");
        var["gCellInfoBuffer"] = dict.getValue<ref<Buffer>>("cellInfoBuffer");

        mpCollectCellInfoPass->execute(pRenderContext, uint3(kSurfelLimit, 1, 1));
    }

    if (mpAccumulateCellInfoPass)
    {
        auto var = mpAccumulateCellInfoPass->getRootVar();

        var["CB"]["gCameraPos"] = mpScene->getCamera()->getPosition();

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");
        var["gSurfelStatus"] = dict.getValue<ref<Buffer>>("surfelStatus");
        var["gCellInfoBuffer"] = dict.getValue<ref<Buffer>>("cellInfoBuffer");

        mpAccumulateCellInfoPass->execute(pRenderContext, uint3(kCellCount, 1, 1));
    }

    if (mpUpdateCellIBPass)
    {
        auto var = mpUpdateCellIBPass->getRootVar();

        var["CB"]["gCameraPos"] = mpScene->getCamera()->getPosition();

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");
        var["gSurfelStatus"] = dict.getValue<ref<Buffer>>("surfelStatus");
        var["gCellInfoBuffer"] = dict.getValue<ref<Buffer>>("cellInfoBuffer");
        var["gCellIndexBuffer"] = dict.getValue<ref<Buffer>>("cellIndexBuffer");

        mpUpdateCellIBPass->execute(pRenderContext, uint3(kSurfelLimit, 1, 1));
    }
}

void SurfelUpdatePass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        mpCollectCellInfoPass = ComputePass::create(
            mpDevice,
            "RenderPasses/Surfel/SurfelUpdatePass/SurfelUpdatePass.cs.slang",
            "collectCellInfo",
            mpScene->getSceneDefines()
        );

        mpAccumulateCellInfoPass = ComputePass::create(
            mpDevice,
            "RenderPasses/Surfel/SurfelUpdatePass/SurfelUpdatePass.cs.slang",
            "accumulateCellInfo",
            mpScene->getSceneDefines()
        );

        mpUpdateCellIBPass = ComputePass::create(
            mpDevice,
            "RenderPasses/Surfel/SurfelUpdatePass/SurfelUpdatePass.cs.slang",
            "updateCellIB",
            mpScene->getSceneDefines()
        );
    }
}
