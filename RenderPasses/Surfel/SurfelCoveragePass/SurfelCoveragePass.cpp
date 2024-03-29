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
        .texture2D(1920 / 16, 1080 / 16);

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

        if (!dict.keyExists("surfelBuffer"))
            createSurfelBuffer(dict);

        var["CB"]["gInvResolution"] = float2(1.0f / resolution.x, 1.0f / resolution.y);
        var["CB"]["gInvViewProj"] = mpScene->getCamera()->getInvViewProjMatrix();
        var["CB"]["gTileSize"] = kTileSize;
        var["CB"]["gSurfelLimit"] = kSurfelLimit;
        var["CB"]["gSurfelRadius"] = kSurfelRadius;
        var["CB"]["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");

        var["gDepth"] = pDepth;
        var["gNormal"] = pNormal;

        var["gCoverage"] = pCoverage;

        pRenderContext->clearUAV(pCoverage->getUAV().get(), uint4(0));
        mpComputePass->execute(pRenderContext, uint3(resolution, 1));
    }
}

void SurfelCoveragePass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        ProgramDesc desc;
        desc.addShaderLibrary("RenderPasses/Surfel/SurfelCoveragePass/SurfelCoveragePass.cs.slang").csEntry("csMain");
        mpComputePass = ComputePass::create(mpDevice, desc, mpScene->getSceneDefines());
    }
}

void SurfelCoveragePass::createSurfelBuffer(Dictionary& dict)
{
    const ref<Buffer> buffer = mpDevice->createStructuredBuffer(
        sizeof(Surfel), kSurfelLimit, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );


    Surfel testSurfelAry[] = {
        {float3(0, 0, 0), float3(0, 1, 0), true},
        {float3(0.02f, 0, 0.02f), float3(0, 1, 0), true},
    };
    buffer->setBlob(&testSurfelAry, 0, sizeof(Surfel) * 2);

    dict["surfelBuffer"] = buffer;
}
