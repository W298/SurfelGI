#include "SurfelGBuffer.h"

const ChannelList SurfelGBuffer::kChannels = {
    {"normal", "gNormal", "Normal", true, ResourceFormat::RGBA32Float},
    {"packedHitInfo", "gPackedHitInfo", "Packed Hit Info", true, ResourceFormat::RGBA32Uint},
    {"instanceIDVisual", "gInstanceIDVisual", "Instance ID Visualization", true, ResourceFormat::RGBA32Float},
};

SurfelGBuffer::SurfelGBuffer(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check for required features.
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_2))
        FALCOR_THROW("requires Shader Model 6.2 support.");
    if (!mpDevice->isFeatureSupported(Device::SupportedFeatures::Barycentrics))
        FALCOR_THROW("requires pixel shader barycentrics support.");
    if (!mpDevice->isFeatureSupported(Device::SupportedFeatures::RasterizerOrderedViews))
        FALCOR_THROW("requires rasterizer ordered views (ROVs) support.");

    // Init graphics state.
    mpState = GraphicsState::create(mpDevice);

    // Create FBO.
    mpFbo = Fbo::create(mpDevice);
}

RenderPassReflection SurfelGBuffer::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    // Output depth
    reflector.addOutput("depth", "depth buffer")
        .format(ResourceFormat::D32Float)
        .bindFlags(ResourceBindFlags::DepthStencil);

    // Output channels
    addRenderPassOutputs(reflector, kChannels, ResourceBindFlags::RenderTarget | ResourceBindFlags::UnorderedAccess);

    return reflector;
}

void SurfelGBuffer::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pDepth = renderData.getTexture("depth");

    if (mpProgram)
    {
        mpFbo->attachDepthStencilTarget(pDepth);

        for (uint32_t i = 0; i < kChannels.size(); ++i)
            mpFbo->attachColorTarget(renderData.getTexture(kChannels[i].name), i);

        pRenderContext->clearDsv(pDepth->getDSV().get(), 1.f, 0);
        pRenderContext->clearFbo(mpFbo.get(), float4(0), 1.f, 0, FboAttachmentType::Color);

        mpState->setFbo(mpFbo);
        mpScene->rasterize(pRenderContext, mpState.get(), mpVars.get());
    }
}

void SurfelGBuffer::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        mpScene->getCamera()->setPosition(float3(-0.1948, 0.1656, 0.4519));
        mpScene->getCamera()->setTarget(float3(0.1823, 0.0117, -0.4614));

        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary("RenderPasses/Surfel/SurfelGBuffer/SurfelGBuffer.3d.slang")
            .vsEntry("vsMain")
            .psEntry("psMain");
        desc.addTypeConformances(mpScene->getTypeConformances());

        mpProgram = Program::create(mpDevice, desc, mpScene->getSceneDefines());
        mpState->setProgram(mpProgram);

        mpVars = ProgramVars::create(mpDevice, mpProgram.get());
    }
}
