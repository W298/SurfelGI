#include "SurfelCoveragePass.h"

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
        .format(ResourceFormat::R32Uint)
        .bindFlags(ResourceBindFlags::UnorderedAccess)
        .texture2D(1920 / 16, 1080 / 16); // #TODO

    return reflector;
}

void SurfelCoveragePass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pDepth = renderData.getTexture("depth");
    const auto& pNormal = renderData.getTexture("normal");

    const auto& pCoverage = renderData.getTexture("coverage");

    FALCOR_ASSERT(pDepth && pNormal && pCoverage);

    const uint2 resolution = uint2(pDepth->getWidth(), pDepth->getHeight());

    if (mpComputePass)
    {
        auto var = mpComputePass->getRootVar();
        auto& dict = renderData.getDictionary();

        var["CB"]["gInvResolution"] = float2(1.f / resolution.x, 1.f / resolution.y);
        var["CB"]["gInvViewProj"] = mpScene->getCamera()->getInvViewProjMatrix();
        var["CB"]["gFrameIndex"] = mFrameIndex;
        var["CB"]["gCameraPos"] = mpScene->getCamera()->getPosition();

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");
        var["gCellInfoBuffer"] = dict.getValue<ref<Buffer>>("cellInfoBuffer");
        var["gCellToSurfelBuffer"] = dict.getValue<ref<Buffer>>("cellToSurfelBuffer");

        var["gDepth"] = pDepth;
        var["gNormal"] = pNormal;

        var["gCoverage"] = pCoverage;

        pRenderContext->clearUAV(pCoverage->getUAV().get(), uint4(0));
        mpComputePass->execute(pRenderContext, uint3(resolution, 1));
    }

    mFrameIndex++;
}

void SurfelCoveragePass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        mpScene->getCamera()->setPosition(float3(-0.0613, 0.1113, 0.1275));
        // mpScene->getCamera()->setTarget(float3(0.0858, -0.1472, -0.4462));

        mpComputePass = ComputePass::create(
            mpDevice,
            "RenderPasses/Surfel/SurfelCoveragePass/SurfelCoveragePass.hlsl",
            "csMain",
            mpScene->getSceneDefines()
        );
    }
}
