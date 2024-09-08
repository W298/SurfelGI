#include "BilateralFilter.h"

BilateralFilter::BilateralFilter(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");

    mpState = ComputeState::create(mpDevice);
}

RenderPassReflection BilateralFilter::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    // Input
    reflector.addInput("input", "input texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::ShaderResource);

    // Output
    reflector.addOutput("output", "output texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    return reflector;
}

void BilateralFilter::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pInput = renderData.getTexture("input");
    const auto& pOutput = renderData.getTexture("output");

    FALCOR_ASSERT(pInput && pOutput);

    if (!mpProgram)
    {
        ProgramDesc desc;
        desc.addShaderLibrary("RenderPasses/Surfel/BilateralFilter/BilateralFilter.cs.slang")
            .csEntry("csMain");

        mpProgram = Program::create(mpDevice, desc);
        mpState->setProgram(mpProgram);
        mpVars = ProgramVars::create(mpDevice, mpProgram.get());
    }

    if (mpProgram)
    {
        auto var = mpVars->getRootVar();

        var["CB"]["gResolution"] = renderData.getDefaultTextureDims();
        var["CB"]["gSigmaD"] = mSigmaD;
        var["CB"]["gSigmaR"] = mSigmaR;

        var["gInput"] = pInput;
        var["gOutput"] = pOutput;

        pRenderContext->clearUAV(pOutput->getUAV().get(), float4(0));

        uint3 threadGroupSize = mpProgram->getReflector()->getThreadGroupSize();
        uint3 groups = div_round_up(uint3(renderData.getDefaultTextureDims(), 1), threadGroupSize);
        pRenderContext->dispatch(mpState.get(), mpVars.get(), groups);
    }
}

void BilateralFilter::renderUI(Gui::Widgets& widget)
{
    widget.slider("Sigma D", mSigmaD, 0.f, 50.f);
    widget.slider("Sigma R", mSigmaR, 0.f, 50.f);
}
