#include "SurfelGenPass.h"
#include "../RenderPasses/Surfel/SurfelTypes.hlsli"

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
        .texture2D(1920 / 16, 1080 / 16); // #TODO
    reflector.addInput("instance", "instance texture")
        .format(ResourceFormat::R32Uint)
        .bindFlags(ResourceBindFlags::ShaderResource);

    // Output
    reflector.addOutput("output", "output texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    return reflector;
}

void SurfelGenPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    const auto& pDepth = renderData.getTexture("depth");
    const auto& pNormal = renderData.getTexture("normal");
    const auto& pCoverage = renderData.getTexture("coverage");
    const auto& pInstance = renderData.getTexture("instance");

    const auto& pOutput = renderData.getTexture("output");

    FALCOR_ASSERT(pDepth && pNormal && pCoverage && pOutput);

    const uint2 resolution = uint2(pDepth->getWidth(), pDepth->getHeight());

    if (mpComputePass)
    {
        auto var = mpComputePass->getRootVar();
        auto& dict = renderData.getDictionary();

        {
            const AnimationController* pAnimationController = mpScene->getAnimationController();
            const GeometryInstanceData& instance = mpScene->getGeometryInstance(157);
            const float4x4& instanceTransform = pAnimationController->getGlobalMatrices()[instance.globalMatrixID];

            float3 scale;
            quatf rotation;
            float3 translation;
            float3 skew;
            float4 perspective;
            math::decompose(instanceTransform, scale, rotation, translation, skew, perspective);

            Transform finalTranform;
            finalTranform.setTranslation(translation);
            finalTranform.setRotationEulerDeg(float3(0, (float)mFrameIndex * 0.01f, 0));
            finalTranform.setScaling(scale);

            mpScene->updateNodeTransform(instance.globalMatrixID, finalTranform.getMatrix());
        }

        mpScene->setRaytracingShaderData(pRenderContext, var);

        var["CB"]["gInvResolution"] = float2(1.f / resolution.x, 1.f / resolution.y);
        var["CB"]["gInvViewProj"] = mpScene->getCamera()->getInvViewProjMatrix();
        var["CB"]["gFrameIndex"] = mFrameIndex;
        var["CB"]["gCameraPos"] = mpScene->getCamera()->getPosition();

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");

        ref<Buffer> surfelStatus = dict.getValue<ref<Buffer>>("surfelStatus");
        mNumSurfels = surfelStatus->getElement<uint>(kSurfelStatus_TotalSurfelCount);
        var["gSurfelStatus"] = surfelStatus;

        var["gCellInfoBuffer"] = dict.getValue<ref<Buffer>>("cellInfoBuffer");
        var["gCellToSurfelBuffer"] = dict.getValue<ref<Buffer>>("cellToSurfelBuffer");

        var["gDepth"] = pDepth;
        var["gNormal"] = pNormal;
        var["gCoverage"] = pCoverage;
        var["gInstance"] = pInstance;

        var["gOutput"] = pOutput;

        pRenderContext->clearUAV(pOutput->getUAV().get(), float4(0));
        mpComputePass->execute(pRenderContext, uint3(resolution, 1));
    }

    mFrameIndex++;
}

void SurfelGenPass::renderUI(Gui::Widgets& widget)
{
    widget.text("frame index: " + std::to_string(mFrameIndex));
    widget.text("num surfels: " + std::to_string(mNumSurfels));

    widget.text("total surfel limit: " + std::to_string(kTotalSurfelLimit));
    widget.text("per cell surfel limit: " + std::to_string(kPerCellSurfelLimit));
    widget.text("coverage threshold: " + std::to_string(kCoverageThreshold));
    widget.text("surfel radius: " + std::to_string(kSurfelRadius));
}

void SurfelGenPass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        mpComputePass = ComputePass::create(
            mpDevice, "RenderPasses/Surfel/SurfelGenPass/SurfelGenPass.cs.slang", "csMain", mpScene->getSceneDefines()
        );
    }
}
