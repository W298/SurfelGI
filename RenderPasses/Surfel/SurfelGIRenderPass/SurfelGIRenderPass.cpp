#include "SurfelGIRenderPass.h"

SurfelGIRenderPass::SurfelGIRenderPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");

    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_DEFAULT);
    FALCOR_ASSERT(mpSampleGenerator);
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
    reflector.addOutput("reflectionLighting", "reflection lighting")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    reflector.addOutput("diffuseLighting", "diffuse lighting")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    reflector.addOutput("blurredReflectionLighting", "blurred reflection lighting")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    reflector.addOutput("finalResult", "final result")
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

    const auto& pReflectionLighting = renderData.getTexture("reflectionLighting");
    const auto& pDiffuseLighting = renderData.getTexture("diffuseLighting");
    const auto& pBlurredReflectionLighting = renderData.getTexture("blurredReflectionLighting");
    const auto& pFinalResult = renderData.getTexture("finalResult");

    if (mpScene)
    {
        // Lighting Pass
        {
            auto var = mpLightingPass->getRootVar();
            mpScene->setRaytracingShaderData(pRenderContext, var);

            var["CB"]["gResolution"] = renderData.getDefaultTextureDims();
            var["CB"]["gFrameIndex"] = mFrameIndex;
            var["CB"]["gRenderDirectLighting"] = mRenderDirectLighting;
            var["CB"]["gRenderIndirectLighting"] = mRenderIndirectLighting;
            var["CB"]["gRenderReflection"] = mRenderReflection;

            var["gHitInfo"] = pHitInfo;
            var["gReflectionHitInfo"] = pReflectionHitInfo;
            var["gReflectionDirection"] = pReflectionDirection;
            var["gDiffuseIndirectLighting"] = pDiffuseIndirectLighting;
            var["gReflectionIndirectLighting"] = pReflectionIndirectLighting;

            var["gReflectionLighting"] = pReflectionLighting;
            var["gDiffuseLighting"] = pDiffuseLighting;

            pRenderContext->clearUAV(pReflectionLighting->getUAV().get(), float4(0));
            pRenderContext->clearUAV(pDiffuseLighting->getUAV().get(), float4(0));

            mpLightingPass->execute(pRenderContext, uint3(renderData.getDefaultTextureDims(), 1u));
        }

        // Blurring Pass
        {
            auto var = mpBlurringPass->getRootVar();

            var["CB"]["gResolution"] = renderData.getDefaultTextureDims();
            var["CB"]["gSigmaD"] = mSigmaD;
            var["CB"]["gSigmaR"] = mSigmaR;

            var["gReflectionLighting"] = pReflectionLighting;
            var["gBlurredReflectionLighting"] = pBlurredReflectionLighting;

            pRenderContext->clearUAV(pBlurredReflectionLighting->getUAV().get(), float4(0));

            mpBlurringPass->execute(pRenderContext, uint3(renderData.getDefaultTextureDims(), 1u));
        }

        // Integrate Pass
        {
            auto var = mpIntegratePass->getRootVar();

            var["gReflectionHitInfo"] = pReflectionHitInfo;
            var["gReflectionDirection"] = pReflectionDirection;
            var["gBlurredReflectionLighting"] = pBlurredReflectionLighting;
            var["gDiffuseLighting"] = pDiffuseLighting;

            var["gFinalResult"] = pFinalResult;

            mpIntegratePass->execute(pRenderContext, uint3(renderData.getDefaultTextureDims(), 1u));
        }
    }

    mFrameIndex++;
}

void SurfelGIRenderPass::renderUI(Gui::Widgets& widget)
{
    widget.checkbox("Direct Lighting", mRenderDirectLighting);
    widget.checkbox("Indirect Lighting", mRenderIndirectLighting);
    widget.checkbox("Reflection", mRenderReflection);

    widget.slider("Sigma D", mSigmaD, 0.f, 50.f);
    widget.slider("Sigma R", mSigmaR, 0.f, 50.f);
}

void SurfelGIRenderPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        mFrameIndex = 0;
        mRenderDirectLighting = true;
        mRenderIndirectLighting = true;
        mRenderReflection = true;

        // Lighting Pass
        {
            auto defines = mpScene->getSceneDefines();
            defines.add(mpSampleGenerator->getDefines());

            ProgramDesc desc;
            desc.addShaderModules(mpScene->getShaderModules());
            desc.addShaderLibrary("RenderPasses/Surfel/SurfelGIRenderPass/LightingPass.cs.slang").csEntry("csMain");
            desc.addTypeConformances(mpScene->getTypeConformances());

            mpLightingPass = ComputePass::create(mpDevice, desc, defines);

            mpSampleGenerator->bindShaderData(mpLightingPass->getRootVar());
        }

        // Blurring Pass
        mpBlurringPass =
            ComputePass::create(mpDevice, "RenderPasses/Surfel/SurfelGIRenderPass/BlurringPass.cs.slang", "csMain");

        // Integrate Pass
        mpIntegratePass =
            ComputePass::create(mpDevice, "RenderPasses/Surfel/SurfelGIRenderPass/IntegratePass.cs.slang", "csMain");
    }
}
