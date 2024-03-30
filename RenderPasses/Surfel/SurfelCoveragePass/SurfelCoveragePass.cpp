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

        var["CB"]["gInvResolution"] = float2(1.f / resolution.x, 1.f / resolution.y);
        var["CB"]["gInvViewProj"] = mpScene->getCamera()->getInvViewProjMatrix();
        var["CB"]["gTileSize"] = kTileSize;
        var["CB"]["gSurfelLimit"] = kSurfelLimit;
        var["CB"]["gSurfelRadius"] = kSurfelRadius;

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");
        var["gSurfelStatus"] = dict.getValue<ref<Buffer>>("surfelStatus");

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
        mpScene->getCamera()->setPosition(float3(-0.2447, 0.2664, 0.4022));
        mpScene->getCamera()->setTarget(float3(0.1015, -0.0460, -0.4825));

        ProgramDesc desc;
        desc.addShaderLibrary("RenderPasses/Surfel/SurfelCoveragePass/SurfelCoveragePass.cs.slang").csEntry("csMain");
        mpComputePass = ComputePass::create(mpDevice, desc, mpScene->getSceneDefines());
    }
}

void SurfelCoveragePass::createSurfelBuffer(Dictionary& dict)
{
    const ref<Buffer> surfelBuffer = mpDevice->createStructuredBuffer(
        sizeof(Surfel), kSurfelLimit, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );

    const ref<Buffer> surfelStatus = mpDevice->createBuffer(sizeof(uint32_t));

    dict["surfelBuffer"] = surfelBuffer;
    dict["surfelStatus"] = surfelStatus;
}
