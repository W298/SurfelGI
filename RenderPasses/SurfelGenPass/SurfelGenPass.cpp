#include "SurfelGenPass.h"

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, SurfelGenPass>();
}

SurfelGenPass::SurfelGenPass(ref<Device> pDevice, const Properties& props)
    : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");
}

Properties SurfelGenPass::getProperties() const
{
    return {};
}

RenderPassReflection SurfelGenPass::reflect(const CompileData& compileData)
{
    // Define the required resources here
    RenderPassReflection reflector;

    reflector.addInput("depth", "depth buffer")
             .format(ResourceFormat::D32Float)
             .bindFlags(ResourceBindFlags::ShaderResource);
    reflector.addInput("raster", "raster data")
             .format(ResourceFormat::RGBA32Float)
             .bindFlags(ResourceBindFlags::ShaderResource);

    reflector.addOutput("output", "output texture")
             .format(ResourceFormat::RGBA32Float)
             .bindFlags(ResourceBindFlags::UnorderedAccess);

    return reflector;
}

void SurfelGenPass::compile(RenderContext* pRenderContext, const CompileData& compileData)
{
}

void SurfelGenPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pDepth = renderData.getTexture("depth");
    const auto& pRaster = renderData.getTexture("raster");
    const auto& pOutput = renderData.getTexture("output");

    FALCOR_ASSERT(pDepth && pRaster && pOutput);

    const uint2 resolution = uint2(pRaster->getWidth(), pRaster->getHeight());

    if (mpSurfelGenPass)
    {
        auto var = mpSurfelGenPass->getRootVar();
        var["PerFrameCB"]["gResolution"] = resolution;
        var["PerFrameCB"]["gInvResolution"] = float2(1.0f / resolution.x, 1.0f / resolution.y);
        var["PerFrameCB"]["gInvViewProj"] = mpScene->getCamera()->getInvViewProjMatrix();

        var["gDepth"] = pDepth;
        var["gRaster"] = pRaster;
        var["gOutput"] = pOutput;

        mpSurfelGenPass->execute(pRenderContext, uint3(resolution, 1));
    }
}

void SurfelGenPass::renderUI(Gui::Widgets& widget)
{
}

void SurfelGenPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        ProgramDesc desc;
        desc.addShaderLibrary("RenderPasses/SurfelGenPass/SurfelGenPass.cs.slang")
            .csEntry("csMain");

        mpSurfelGenPass = ComputePass::create(mpDevice, desc, mpScene->getSceneDefines());
    }
}
