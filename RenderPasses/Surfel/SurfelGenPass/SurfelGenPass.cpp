#include "SurfelGenPass.h"
#include "../RenderPasses/Surfel/SurfelTypes.hlsli"
#include "RenderGraph/RenderPassHelpers.h"

SurfelGenPass::SurfelGenPass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");

    mpFence = mpDevice->createFence();

    mFrameIndex = 0;

    mReadBackBuffer = mpDevice->createBuffer(
        sizeof(uint) * _countof(kInitialStatus), ResourceBindFlags::None, MemoryType::ReadBack, nullptr
    );
    mReadBackValid = false;

    mMovement[Input::Key::Right] = false;
    mMovement[Input::Key::Up] = false;
    mMovement[Input::Key::Down] = false;
    mMovement[Input::Key::Left] = false;
    mMovement[Input::Key::R] = false;

    mIsMoving = false;
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
        .texture2D(compileData.defaultTexDims.x / kTileSize.x, compileData.defaultTexDims.y / kTileSize.y);
    reflector.addInput("packedHitInfo", "packed hit info texture")
        .format(ResourceFormat::RGBA32Uint)
        .bindFlags(ResourceBindFlags::ShaderResource);

    // Output
    reflector.addOutput("output", "output texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    return reflector;
}

void SurfelGenPass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    mReadBackValid = false;

    const auto& pDepth = renderData.getTexture("depth");
    const auto& pNormal = renderData.getTexture("normal");
    const auto& pCoverage = renderData.getTexture("coverage");
    const auto& pPackedHitInfo = renderData.getTexture("packedHitInfo");

    const auto& pOutput = renderData.getTexture("output");

    FALCOR_ASSERT(pDepth && pNormal && pCoverage && pOutput);

    uint2 resolution = uint2(pDepth->getWidth(), pDepth->getHeight());

    if (mpComputePass)
    {
        auto var = mpComputePass->getRootVar();
        auto& dict = renderData.getDictionary();
        ref<Buffer> surfelCounter = dict.getValue<ref<Buffer>>("surfelCounter");

        if (mIsMoving)
        {
            const AnimationController* pAnimationController = mpScene->getAnimationController();
            const GeometryInstanceData& instance = mpScene->getGeometryInstance(698);
            const float4x4& instanceTransform = pAnimationController->getGlobalMatrices()[instance.globalMatrixID];

            float3 scale;
            quatf rotation;
            float3 translation;
            float3 skew;
            float4 perspective;
            math::decompose(instanceTransform, scale, rotation, translation, skew, perspective);

            float speed = 0.001f;

            float dx = mMovement[Input::Key::Right] ? speed : mMovement[Input::Key::Left] ? -speed : 0;
            float dz = mMovement[Input::Key::Up] ? -speed : mMovement[Input::Key::Down] ? speed : 0;
            float3 tDelta = float3(dx, 0, dz);

            float3 rDelta = float3(0, mMovement[Input::Key::R] ? speed * 4 : 0, 0);

            Transform finalTransform;
            finalTransform.setTranslation(translation + tDelta);
            finalTransform.setRotation(rotation);
            finalTransform.setScaling(scale);

            mpScene->updateNodeTransform(instance.globalMatrixID, finalTransform.getMatrix());
        }

        mpScene->setRaytracingShaderData(pRenderContext, var);

        var["CB"]["gResolution"] = resolution;
        var["CB"]["gInvResolution"] = float2(1.f / resolution.x, 1.f / resolution.y);
        var["CB"]["gInvViewProj"] = mpScene->getCamera()->getInvViewProjMatrix();
        var["CB"]["gFrameIndex"] = mFrameIndex;
        var["CB"]["gCameraPos"] = mpScene->getCamera()->getPosition();

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");
        var["gSurfelFreeIndexBuffer"] = dict.getValue<ref<Buffer>>("surfelFreeIndexBuffer");
        var["gSurfelValidIndexBuffer"] = dict.getValue<ref<Buffer>>("surfelValidIndexBuffer");
        var["gSurfelCounter"] = surfelCounter;
        var["gCellInfoBuffer"] = dict.getValue<ref<Buffer>>("cellInfoBuffer");
        var["gCellToSurfelBuffer"] = dict.getValue<ref<Buffer>>("cellToSurfelBuffer");

        var["gDepth"] = pDepth;
        var["gNormal"] = pNormal;
        var["gCoverage"] = pCoverage;
        var["gPackedHitInfo"] = pPackedHitInfo;

        var["gOutput"] = pOutput;

        pRenderContext->clearUAV(pOutput->getUAV().get(), float4(0));
        mpComputePass->execute(pRenderContext, uint3(resolution, 1));

        pRenderContext->copyResource(mReadBackBuffer.get(), surfelCounter.get());
        pRenderContext->submit(false);
        pRenderContext->signal(mpFence.get());

        mReadBackValid = true;
    }

    mFrameIndex++;
}

void SurfelGenPass::renderUI(Gui::Widgets& widget)
{
    widget.text("Frame index\t\t" + std::to_string(mFrameIndex));

    if (mReadBackValid)
    {
        widget.text("Valid surfel count\t\t" + std::to_string(mReadBackBuffer->getElement<uint>(0)));
        widget.text("Free surfel count\t\t" + std::to_string(mReadBackBuffer->getElement<int>(1)));
        widget.text("Valid cell count\t\t" + std::to_string(mReadBackBuffer->getElement<uint>(2)));
    }

    widget.dummy("#spacer0", {1, 20});

    widget.text("Total surfel limit\t\t" + std::to_string(kTotalSurfelLimit));
    widget.text("Per cell surfel limit\t\t" + std::to_string(kPerCellSurfelLimit));
    widget.text("Coverage threshold\t\t" + std::to_string(kCoverageThreshold));
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

bool SurfelGenPass::onKeyEvent(const KeyboardEvent& keyEvent)
{
    mIsMoving = keyEvent.type != KeyboardEvent::Type::KeyReleased;
    mMovement[keyEvent.key] = mIsMoving;

    return false;
}
