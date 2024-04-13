#include "SurfelUpdatePass.h"
#include "../RenderPasses/Surfel/SurfelTypes.hlsli"
#include "Utils/Math/FalcorMath.h"

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

        mpScene->setRaytracingShaderData(pRenderContext, var);

        var["CB"]["gCameraPos"] = mpScene->getCamera()->getPosition();
        var["CB"]["gResolution"] = renderData.getDefaultTextureDims();
        var["CB"]["gFOVy"] = mFOVy;

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");
        
        var["gSurfelDirtyIndexBuffer"] = dict.getValue<ref<Buffer>>("surfelDirtyIndexBuffer");
        var["gSurfelValidIndexBuffer"] = dict.getValue<ref<Buffer>>("surfelValidIndexBuffer");
        var["gSurfelFreeIndexBuffer"] = dict.getValue<ref<Buffer>>("surfelFreeIndexBuffer");

        var["gSurfelCounter"] = dict.getValue<ref<Buffer>>("surfelCounter");
        var["gSurfelConfig"] = dict.getValue<ref<Buffer>>("surfelConfig");

        var["gCellInfoBuffer"] = dict.getValue<ref<Buffer>>("cellInfoBuffer");

        mpCollectCellInfoPass->execute(pRenderContext, uint3(kTotalSurfelLimit, 1, 1));
    }

    if (mpAccumulateCellInfoPass)
    {
        auto var = mpAccumulateCellInfoPass->getRootVar();

        var["CB"]["gCameraPos"] = mpScene->getCamera()->getPosition();

        var["gSurfelCounter"] = dict.getValue<ref<Buffer>>("surfelCounter");
        var["gCellInfoBuffer"] = dict.getValue<ref<Buffer>>("cellInfoBuffer");

        mpAccumulateCellInfoPass->execute(pRenderContext, uint3(kCellCount, 1, 1));
    }

    if (mpUpdateCellToSurfelBuffer)
    {
        auto var = mpUpdateCellToSurfelBuffer->getRootVar();

        var["CB"]["gCameraPos"] = mpScene->getCamera()->getPosition();

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");
        var["gSurfelValidIndexBuffer"] = dict.getValue<ref<Buffer>>("surfelValidIndexBuffer");
        var["gSurfelCounter"] = dict.getValue<ref<Buffer>>("surfelCounter");
        var["gCellInfoBuffer"] = dict.getValue<ref<Buffer>>("cellInfoBuffer");
        var["gCellToSurfelBuffer"] = dict.getValue<ref<Buffer>>("cellToSurfelBuffer");

        mpUpdateCellToSurfelBuffer->execute(pRenderContext, uint3(kTotalSurfelLimit, 1, 1));
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

        mpUpdateCellToSurfelBuffer = ComputePass::create(
            mpDevice,
            "RenderPasses/Surfel/SurfelUpdatePass/SurfelUpdatePass.cs.slang",
            "updateCellToSurfelBuffer",
            mpScene->getSceneDefines()
        );

        mFOVy = focalLengthToFovY(mpScene->getCamera()->getFocalLength(), mpScene->getCamera()->getFrameHeight());
    }
}
