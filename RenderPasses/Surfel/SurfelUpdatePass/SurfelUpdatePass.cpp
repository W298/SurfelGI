#include "SurfelUpdatePass.h"
#include "Utils/Math/FalcorMath.h"
#include "../SurfelResource.h"

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

        var[kSurfelBufferVarName] = getSurfelBuffer(mpDevice, dict);
        var[kSurfelDirtyIndexBufferVarName] = getSurfelDirtyIndexBuffer(mpDevice, dict);
        var[kSurfelValidIndexBufferVarName] = getSurfelValidIndexBuffer(mpDevice, dict);
        var[kSurfelFreeIndexBufferVarName] = getSurfelFreeIndexBuffer(mpDevice, dict);
        var[kCellInfoBufferVarName] = getCellInfoBuffer(mpDevice, dict);

        var[kSurfelCounterVarName] = getSurfelCounter(mpDevice, dict);
        var[kSurfelConfigVarName] = getSurfelConfig(mpDevice, dict);

        mpCollectCellInfoPass->execute(pRenderContext, uint3(kTotalSurfelLimit, 1, 1));
    }

    if (mpAccumulateCellInfoPass)
    {
        auto var = mpAccumulateCellInfoPass->getRootVar();

        var["CB"]["gCameraPos"] = mpScene->getCamera()->getPosition();

        var[kCellInfoBufferVarName] = getCellInfoBuffer(mpDevice, dict);
        var[kSurfelCounterVarName] = getSurfelCounter(mpDevice, dict);

        mpAccumulateCellInfoPass->execute(pRenderContext, uint3(kCellCount, 1, 1));
    }

    if (mpUpdateCellToSurfelBuffer)
    {
        auto var = mpUpdateCellToSurfelBuffer->getRootVar();

        var["CB"]["gCameraPos"] = mpScene->getCamera()->getPosition();

        var[kSurfelBufferVarName] = getSurfelBuffer(mpDevice, dict);
        var[kSurfelValidIndexBufferVarName] = getSurfelValidIndexBuffer(mpDevice, dict);
        var[kCellInfoBufferVarName] = getCellInfoBuffer(mpDevice, dict);
        var[kCellToSurfelBufferVarName] = getCellToSurfelBuffer(mpDevice, dict);

        var[kSurfelCounterVarName] = getSurfelCounter(mpDevice, dict);
        var[kSurfelConfigVarName] = getSurfelConfig(mpDevice, dict);

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
