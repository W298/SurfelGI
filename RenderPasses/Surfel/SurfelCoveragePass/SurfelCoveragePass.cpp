#include "SurfelCoveragePass.h"
#include "../SurfelResource.h"

SurfelCoveragePass::SurfelCoveragePass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");
}

RenderPassReflection SurfelCoveragePass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    // Input
    reflector.addInput("depth", "depth buffer")
        .format(ResourceFormat::D32Float)
        .bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput("normal", "normal texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::ShaderResource);

    // Output
    reflector.addOutput("coverage", "coverage texture")
        .format(ResourceFormat::RG32Uint)
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .texture2D(compileData.defaultTexDims.x / kTileSize.x, compileData.defaultTexDims.y / kTileSize.y);

    reflector.addOutput("debug", "debug texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    return reflector;
}

void SurfelCoveragePass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pDepth = renderData.getTexture("depth");
    const auto& pNormal = renderData.getTexture("normal");

    const auto& pCoverage = renderData.getTexture("coverage");
    const auto& pDebug = renderData.getTexture("debug");

    FALCOR_ASSERT(pDepth && pNormal && pCoverage && pDebug);

    const uint2 resolution = uint2(pDepth->getWidth(), pDepth->getHeight());

    if (mpComputePass)
    {
        auto var = mpComputePass->getRootVar();
        auto& dict = renderData.getDictionary();

        var["CB"]["gInvResolution"] = float2(1.f / resolution.x, 1.f / resolution.y);
        var["CB"]["gInvViewProj"] = mpScene->getCamera()->getInvViewProjMatrix();
        var["CB"]["gFrameIndex"] = mFrameIndex;
        var["CB"]["gCameraPos"] = mpScene->getCamera()->getPosition();

        var[kSurfelBufferVarName] = getSurfelBuffer(mpDevice, dict);
        var[kCellInfoBufferVarName] = getCellInfoBuffer(mpDevice, dict);
        var[kCellToSurfelBufferVarName] = getCellToSurfelBuffer(mpDevice, dict);

        var[kSurfelConfigVarName] = getSurfelConfig(mpDevice, dict);

        var["gDepth"] = pDepth;
        var["gNormal"] = pNormal;

        var["gCoverage"] = pCoverage;
        var["gDebug"] = pDebug;

        pRenderContext->clearUAV(pCoverage->getUAV().get(), uint4(0));
        pRenderContext->clearUAV(pDebug->getUAV().get(), float4(0));
        mpComputePass->execute(pRenderContext, uint3(resolution, 1));
    }

    mFrameIndex++;
}

void SurfelCoveragePass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        mpComputePass = ComputePass::create(
            mpDevice,
            "RenderPasses/Surfel/SurfelCoveragePass/SurfelCoveragePass.cs.slang",
            "csMain",
            mpScene->getSceneDefines()
        );
    }
}
