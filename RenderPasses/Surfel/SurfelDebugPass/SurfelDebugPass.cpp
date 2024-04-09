#include "SurfelDebugPass.h"

SurfelDebugPass::SurfelDebugPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check for required features.
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_2))
        FALCOR_THROW("requires Shader Model 6.2 support.");

    // Init graphics state.
    mpState = GraphicsState::create(mpDevice);

    // Set rasterizer function.
    RasterizerState::Desc desc;
    desc.setFillMode(RasterizerState::FillMode::Wireframe);
    desc.setCullMode(RasterizerState::CullMode::None);
    mpRasterState = RasterizerState::create(desc);

    mpState->setRasterizerState(mpRasterState);

    // Create FBO.
    mpFbo = Fbo::create(mpDevice);
}

RenderPassReflection SurfelDebugPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    // Output depth
    reflector.addOutput("depth", "depth buffer")
        .format(ResourceFormat::D32Float)
        .bindFlags(ResourceBindFlags::DepthStencil);

    // Output channels
    reflector.addOutput("debug", "debug texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::RenderTarget);

    return reflector;
}

void SurfelDebugPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pDepth = renderData.getTexture("depth");
    const auto& pDebug = renderData.getTexture("debug");

    if (mpProgram)
    {
        mpFbo->attachDepthStencilTarget(pDepth);
        mpFbo->attachColorTarget(pDebug, 0);

        pRenderContext->clearDsv(pDepth->getDSV().get(), 1.f, 0);
        pRenderContext->clearFbo(mpFbo.get(), float4(0), 1.f, 0, FboAttachmentType::Color);

        mpState->setFbo(mpFbo);
        mpScene->rasterize(pRenderContext, mpState.get(), mpVars.get(), mpRasterState, mpRasterState);
    }
}

void SurfelDebugPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary("RenderPasses/Surfel/SurfelDebugPass/SurfelDebugPass.3d.slang")
            .vsEntry("vsMain")
            .psEntry("psMain");
        desc.addTypeConformances(mpScene->getTypeConformances());

        mpProgram = Program::create(mpDevice, desc, mpScene->getSceneDefines());
        mpState->setProgram(mpProgram);

        mpVars = ProgramVars::create(mpDevice, mpProgram.get());
    }
}
