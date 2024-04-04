#include "SurfelGenPass.h"

SurfelGenPass::SurfelGenPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");

    mFrameIndex = 0;
}

RenderPassReflection SurfelGenPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    // Input
    reflector.addInput("depth", "depth buffer")
        .format(ResourceFormat::D32Float)
        .bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput("normal", "normal texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput("coverage", "coverage texture")
        .format(ResourceFormat::R32Uint)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .texture2D(1920 / 16, 1080 / 16);

    // Output
    reflector.addOutput("output", "output texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    reflector.addOutput("debug", "debug texture")
        .format(ResourceFormat::R32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    return reflector;
}

void SurfelGenPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pDepth = renderData.getTexture("depth");
    const auto& pNormal = renderData.getTexture("normal");
    const auto& pCoverage = renderData.getTexture("coverage");

    const auto& pOutput = renderData.getTexture("output");
    const auto& pDebug = renderData.getTexture("debug");

    FALCOR_ASSERT(pDepth && pNormal && pCoverage && pOutput);

    const uint2 resolution = uint2(pDepth->getWidth(), pDepth->getHeight());

    if (mpComputePass)
    {
        auto var = mpComputePass->getRootVar();
        auto& dict = renderData.getDictionary();

        var["CB"]["gInvResolution"] = float2(1.f / resolution.x, 1.f / resolution.y);
        var["CB"]["gInvViewProj"] = mpScene->getCamera()->getInvViewProjMatrix();
        var["CB"]["gFrameIndex"] = mFrameIndex;

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");

        ref<Buffer> surfelStatus = dict.getValue<ref<Buffer>>("surfelStatus");
        mNumSurfels = surfelStatus->getElement<uint32_t>(0);
        var["gSurfelStatus"] = surfelStatus;

        var["gDepth"] = pDepth;
        var["gNormal"] = pNormal;
        var["gCoverage"] = pCoverage;

        var["gOutput"] = pOutput;
        var["gDebug"] = pDebug;

        pRenderContext->clearUAV(pOutput->getUAV().get(), float4(0));
        mpComputePass->execute(pRenderContext, uint3(resolution, 1));
    }

    mFrameIndex++;
}

void SurfelGenPass::renderUI(Gui::Widgets& widget)
{
    widget.text("frame index: " + std::to_string(mFrameIndex));
    widget.text("num surfels: " + std::to_string(mNumSurfels));
}

void SurfelGenPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        ProgramDesc desc;
        desc.addShaderLibrary("RenderPasses/Surfel/SurfelGenPass/SurfelGenPass.cs.slang").csEntry("csMain");
        mpComputePass = ComputePass::create(mpDevice, desc, mpScene->getSceneDefines());
    }
}
