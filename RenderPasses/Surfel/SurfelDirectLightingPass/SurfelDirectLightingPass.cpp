#include "SurfelDirectLightingPass.h"

SurfelDirectLightingPass::SurfelDirectLightingPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
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

RenderPassReflection SurfelDirectLightingPass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    // Input
    reflector.addInput("packedHitInfo", "packed hit info texture")
        .format(ResourceFormat::RGBA32Uint)
        .bindFlags(ResourceBindFlags::ShaderResource);

    // Output
    reflector.addOutput("output", "output texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    return reflector;
}

void SurfelDirectLightingPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pPackedHitInfo = renderData.getTexture("packedHitInfo");
    const auto& pOutput = renderData.getTexture("output");

    FALCOR_ASSERT(pPackedHitInfo && pOutput);

    if (mpProgram)
    {
        auto var = mpVars->getRootVar();
        mpScene->setRaytracingShaderData(pRenderContext, var);

        var["CB"]["gResolution"] = renderData.getDefaultTextureDims();
        var["CB"]["gFrameIndex"] = mFrameIndex;

        var["gPackedHitInfo"] = pPackedHitInfo;
        var["gOutput"] = pOutput;

        pRenderContext->clearUAV(pOutput->getUAV().get(), float4(0));

        uint3 threadGroupSize = mpProgram->getReflector()->getThreadGroupSize();
        uint3 groups = div_round_up(uint3(renderData.getDefaultTextureDims(), 1), threadGroupSize);
        pRenderContext->dispatch(mpState.get(), mpVars.get(), groups);
    }

    mFrameIndex++;
}

void SurfelDirectLightingPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary("RenderPasses/Surfel/SurfelDirectLightingPass/SurfelDirectLightingPass.cs.slang")
            .csEntry("csMain");
        desc.addTypeConformances(mpScene->getTypeConformances());

        mpProgram = Program::create(mpDevice, desc, mpScene->getSceneDefines());
        mpProgram->addDefines(mpSampleGenerator->getDefines());

        mpState->setProgram(mpProgram);

        mpVars = ProgramVars::create(mpDevice, mpProgram.get());
        mpSampleGenerator->bindShaderData(mpVars->getRootVar());
    }
}
