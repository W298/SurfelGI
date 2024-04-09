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
    RasterizerState::Desc desc;
    desc.setFillMode(RasterizerState::FillMode::Solid);
    desc.setCullMode(RasterizerState::CullMode::Back);
    mpRasterState = RasterizerState::create(desc);

    mpState->setRasterizerState(mpRasterState);

    // Create FBO.
    mpFbo = Fbo::create(mpDevice);
}

RenderPassReflection DirectIlluminationPass::reflect(const CompileData& compileData)
{
    // Define the required resources here
    RenderPassReflection reflector;

    reflector.addOutput("raster", "raster texture").format(ResourceFormat::RGBA32Float);

    return reflector;
}

void DirectIlluminationPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pOutput = renderData.getTexture("raster");

    FALCOR_ASSERT(pOutput);

    if (!mpDepth)
    {
        // Create depth buffer.
        mpDepth = mpDevice->createTexture2D(
            renderData.getDefaultTextureDims().x,
            renderData.getDefaultTextureDims().y,
            ResourceFormat::D32Float,
            1,
            Resource::kMaxPossible,
            nullptr,
            ResourceBindFlags::DepthStencil
        );
    }

    mpFbo->attachColorTarget(pOutput, 0);
    mpFbo->attachDepthStencilTarget(mpDepth);

    pRenderContext->clearDsv(mpDepth->getDSV().get(), 1.f, 0);
    pRenderContext->clearFbo(mpFbo.get(), float4(0.2f, 0.2f, 0.2f, 1.f), 1.f, 0, FboAttachmentType::Color);

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
