#include "SurfelGIRenderPass.h"

SurfelGIRenderPass::SurfelGIRenderPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");

    mpState = ComputeState::create(mpDevice);

    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_DEFAULT);
    FALCOR_ASSERT(mpSampleGenerator);

    mFrameIndex = 0;
}

RenderPassReflection SurfelGIRenderPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    // Input
    reflector.addInput("hitInfo", "hit info texture")
        .format(ResourceFormat::RGBA32Uint)
        .bindFlags(ResourceBindFlags::ShaderResource);

    reflector.addInput("reflectionHitInfo", "reflection hit info texture")
        .format(ResourceFormat::RGBA32Uint)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .flags(RenderPassReflection::Field::Flags::Optional);

    reflector.addInput("reflectionDirection", "reflection direction texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .flags(RenderPassReflection::Field::Flags::Optional);

    reflector.addInput("diffuseIndirectLighting", "diffuse indirect lighting texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .flags(RenderPassReflection::Field::Flags::Optional);

    reflector.addInput("reflectionIndirectLighting", "reflection indirect lighting texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::ShaderResource)
        .flags(RenderPassReflection::Field::Flags::Optional);

    // Output
    reflector.addOutput("output", "output texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    return reflector;
}

void SurfelGIRenderPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pHitInfo = renderData.getTexture("hitInfo");
    const auto& pReflectionHitInfo = renderData.getTexture("reflectionHitInfo");
    const auto& pReflectionDirection = renderData.getTexture("reflectionDirection");
    const auto& pDiffuseIndirectLighting = renderData.getTexture("diffuseIndirectLighting");
    const auto& pReflectionIndirectLighting = renderData.getTexture("reflectionIndirectLighting");

    const auto& pOutput = renderData.getTexture("output");

    FALCOR_ASSERT(pHitInfo && pOutput);

    if (mpProgram)
    {
        auto var = mpVars->getRootVar();
        mpScene->setRaytracingShaderData(pRenderContext, var);

        var["CB"]["gResolution"] = renderData.getDefaultTextureDims();
        var["CB"]["gFrameIndex"] = mFrameIndex;
        var["CB"]["gRenderDirectLighting"] = mRenderDirectLighting;
        var["CB"]["gRenderIndirectLighting"] = mRenderIndirectLighting;
        var["CB"]["gRenderReflection"] = mRenderReflection;

        var["gHitInfo"] = pHitInfo;

        if (pReflectionHitInfo != nullptr)              var["gReflectionHitInfo"] = pReflectionHitInfo;
        if (pReflectionDirection != nullptr)            var["gReflectionDirection"] = pReflectionDirection;
        if (pDiffuseIndirectLighting != nullptr)        var["gDiffuseIndirectLighting"] = pDiffuseIndirectLighting;
        if (pReflectionIndirectLighting != nullptr)     var["gReflectionIndirectLighting"] = pReflectionIndirectLighting;

        var["gOutput"] = pOutput;

        pRenderContext->clearUAV(pOutput->getUAV().get(), float4(0));

        uint3 threadGroupSize = mpProgram->getReflector()->getThreadGroupSize();
        uint3 groups = div_round_up(uint3(renderData.getDefaultTextureDims(), 1), threadGroupSize);
        pRenderContext->dispatch(mpState.get(), mpVars.get(), groups);
    }

    mFrameIndex++;
}

void SurfelGIRenderPass::renderUI(Gui::Widgets& widget)
{
    widget.checkbox("Direct Lighting", mRenderDirectLighting);
    widget.checkbox("Indirect Lighting", mRenderIndirectLighting);
    widget.checkbox("Reflection", mRenderReflection);
}

void SurfelGIRenderPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mRenderDirectLighting = true;
    mRenderIndirectLighting = true;
    mRenderReflection = true;

    if (mpScene)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary("RenderPasses/Surfel/SurfelGIRenderPass/SurfelGIRenderPass.cs.slang")
            .csEntry("csMain");
        desc.addTypeConformances(mpScene->getTypeConformances());

        mpProgram = Program::create(mpDevice, desc, mpScene->getSceneDefines());
        mpProgram->addDefines(mpSampleGenerator->getDefines());

        mpState->setProgram(mpProgram);

        mpVars = ProgramVars::create(mpDevice, mpProgram.get());
        mpSampleGenerator->bindShaderData(mpVars->getRootVar());
    }
}
