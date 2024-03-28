#include "DirectIlluminationPass.h"

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, DirectIlluminationPass>();
}

DirectIlluminationPass::DirectIlluminationPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");

    // Init graphics state.
    mpState = GraphicsState::create(mpDevice);

    // Set rasterizer function.
    RasterizerState::Desc wireframeDesc;
    wireframeDesc.setFillMode(RasterizerState::FillMode::Solid);
    wireframeDesc.setCullMode(RasterizerState::CullMode::Back);
    mpRasterState = RasterizerState::create(wireframeDesc);

    mpState->setRasterizerState(mpRasterState);

    // Create FBO.
    mpFbo = Fbo::create(mpDevice);
}

RenderPassReflection DirectIlluminationPass::reflect(const CompileData& compileData)
{
    // Define the required resources here
    RenderPassReflection reflector;

    reflector.addOutput("depth", "depth buffer")
        .format(ResourceFormat::D32Float)
        .bindFlags(ResourceBindFlags::DepthStencil);

    reflector.addOutput("normal", "normal texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    reflector.addOutput("raster", "raster texture").format(ResourceFormat::RGBA32Float);

    return reflector;
}

void DirectIlluminationPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pDepth = renderData.getTexture("depth");
    const auto& pNormal = renderData.getTexture("normal");
    const auto& pOutput = renderData.getTexture("raster");

    FALCOR_ASSERT(pDepth && pNormal && pOutput);

    mpFbo->attachColorTarget(pOutput, 0);
    mpFbo->attachDepthStencilTarget(pDepth);

    pRenderContext->clearDsv(pDepth->getDSV().get(), 1.f, 0);
    pRenderContext->clearUAV(pNormal->getUAV().get(), float4(0));
    pRenderContext->clearFbo(mpFbo.get(), float4(0), 1.f, 0, FboAttachmentType::Color);

    mpState->setFbo(mpFbo);

    if (mpScene)
        mpScene->rasterize(pRenderContext, mpState.get(), mpVars.get(), mpRasterState, mpRasterState);
}

void DirectIlluminationPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    // Create wireframe pass program.
    if (mpScene)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary("RenderPasses/DirectIlluminationPass/DirectIlluminationPass.3d.slang")
            .vsEntry("vsMain")
            .psEntry("psMain");
        desc.addTypeConformances(mpScene->getTypeConformances());

        mpProgram = Program::create(mpDevice, desc, mpScene->getSceneDefines());
        mpState->setProgram(mpProgram);

        // Create program vars.
        mpVars = ProgramVars::create(mpDevice, mpProgram.get());
    }
}
