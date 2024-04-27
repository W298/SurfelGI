#include "SurfelGI.h"
#include "Utils/Math/FalcorMath.h"
#include "SurfelTypes.slang"

namespace
{
float plotFunc(void* data, int i)
{
    return static_cast<float*>(data)[i];
}

const std::string kOutputTextureName = "output";
const std::string kDepthTextureName = "depth";
const std::string kNormalTextureName = "normal";
const std::string kPackedHitInfoTextureName = "packedHitInfo";
const std::string kDirectLightingTextureName = "directLighting";

const std::string kSurfelBufferVarName = "gSurfelBuffer";
const std::string kSurfelValidIndexBufferVarName = "gSurfelValidIndexBuffer";
const std::string kSurfelDirtyIndexBufferVarName = "gSurfelDirtyIndexBuffer";
const std::string kSurfelFreeIndexBufferVarName = "gSurfelFreeIndexBuffer";
const std::string kCellInfoBufferVarName = "gCellInfoBuffer";
const std::string kCellToSurfelBufferVarName = "gCellToSurfelBuffer";
const std::string kSurfelRayResultBufferVarName = "gSurfelRayResultBuffer";
const std::string kSurfelCounterVarName = "gSurfelCounter";
const std::string kSurfelConfigVarName = "gSurfelConfig";

SurfelConfig configValue = SurfelConfig();

float surfelVisualRadius = 0.7f;
bool collectDirectLighting = false;
} // namespace

SurfelGI::SurfelGI(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    mpDevice = pDevice;

    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SurfelGI requires Shader Model 6.5 support.");
    if (!mpDevice->isFeatureSupported(Device::SupportedFeatures::RaytracingTier1_1))
        FALCOR_THROW("SurfelGI requires Raytracing Tier 1.1 support.");

    mpFence = mpDevice->createFence();
    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_UNIFORM);
}

RenderPassReflection SurfelGI::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflectInput(reflector, compileData.defaultTexDims);
    reflectOutput(reflector, compileData.defaultTexDims);

    if (math::any(mFrameDim != compileData.defaultTexDims))
    {
        mIsResourceDirty = true;
        mFrameDim = compileData.defaultTexDims;
    }

    return reflector;
}

void SurfelGI::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene)
        return;

    if (mIsResourceDirty)
    {
        createTextureResources();
        bindResources(renderData);
        mIsResourceDirty = false;
    }

    mFOVy = focalLengthToFovY(mpScene->getCamera()->getFocalLength(), mpScene->getCamera()->getFrameHeight());
    mCamPos = mpScene->getCamera()->getPosition();
    mInvViewProj = mpScene->getCamera()->getInvViewProjMatrix();

    // Prepare Pass
    {
        mpPreparePass->execute(pRenderContext, uint3(1));
        pRenderContext->copyResource(mpSurfelDirtyIndexBuffer.get(), mpSurfelValidIndexBuffer.get());
    }

    // Update Pass (Collect Cell Info Pass)
    {
        auto var = mpCollectCellInfoPass->getRootVar();

        mpScene->setRaytracingShaderData(pRenderContext, var);

        var["CB"]["gCameraPos"] = mCamPos;
        var["CB"]["gResolution"] = mFrameDim;
        var["CB"]["gFOVy"] = mFOVy;

        mpCollectCellInfoPass->execute(pRenderContext, uint3(kTotalSurfelLimit, 1, 1));
    }

    // Update Pass (Accumulate Cell Info Pass)
    {
        auto var = mpAccumulateCellInfoPass->getRootVar();

        var["CB"]["gCameraPos"] = mCamPos;

        mpAccumulateCellInfoPass->execute(pRenderContext, uint3(kCellCount, 1, 1));
    }

    // Update Pass (Update Cell To Surfel buffer Pass)
    {
        auto var = mpUpdateCellToSurfelBuffer->getRootVar();

        var["CB"]["gCameraPos"] = mCamPos;

        mpUpdateCellToSurfelBuffer->execute(pRenderContext, uint3(kTotalSurfelLimit, 1, 1));
    }

    // Surfel RayTrace Pass
    {
        auto var = mRtPass.pVars->getRootVar();
        var["CB"]["gFrameIndex"] = mFrameIndex;
        var["CB"]["gCollectDirectLighting"] = collectDirectLighting;

        mpScene->raytrace(pRenderContext, mRtPass.pProgram.get(), mRtPass.pVars, uint3(kRayBudget, 1, 1));
    }

    // Surfel Generation Pass
    {
        auto var = mpSurfelGenerationPass->getRootVar();

        mpScene->setRaytracingShaderData(pRenderContext, var);

        var["CB"]["gResolution"] = mFrameDim;
        var["CB"]["gInvResolution"] = float2(1.f / mFrameDim.x, 1.f / mFrameDim.y);
        var["CB"]["gFOVy"] = mFOVy;
        var["CB"]["gInvViewProj"] = mInvViewProj;
        var["CB"]["gFrameIndex"] = mFrameIndex;
        var["CB"]["gCameraPos"] = mCamPos;

        mpSurfelGenerationPass->execute(pRenderContext, uint3(mFrameDim, 1));
    }

    // Surfel Integrate Pass
    {
        auto var = mpSurfelIntegratePass->getRootVar();

        mpScene->setRaytracingShaderData(pRenderContext, var);

        var["CB"]["gResolution"] = mFrameDim;
        var["CB"]["gSurfelVisualRadius"] = surfelVisualRadius;

        pRenderContext->clearUAV(mpOutputTexture->getUAV().get(), float4(0));
        mpSurfelIntegratePass->execute(pRenderContext, uint3(mFrameDim, 1));
    }

    // Read Back
    {
        pRenderContext->copyResource(mpReadBackBuffer.get(), mpSurfelCounter.get());

        if (mApply)
        {
            pRenderContext->copyResource(mpSurfelBuffer.get(), mpEmptySurfelBuffer.get());
            mpSurfelConfig->setBlob(&configValue, 0, sizeof(SurfelConfig));
            mApply = false;
        }

        pRenderContext->submit(false);
        pRenderContext->signal(mpFence.get());

        mReadBackValid = true;
    }

    mFrameIndex++;
}

void SurfelGI::renderUI(Gui::Widgets& widget)
{
    widget.text("Frame index");
    widget.text(std::to_string(mFrameIndex), true);

    if (mReadBackValid)
    {
        const uint validSurfelCount = mpReadBackBuffer->getElement<uint>(0);
        const uint requestedRayCount = mpReadBackBuffer->getElement<uint>(4);

        std::rotate(mPlotData.begin(), mPlotData.begin() + 1, mPlotData.end());
        mPlotData[mPlotData.size() - 1] = (float)validSurfelCount / kTotalSurfelLimit;

        widget.graph("", plotFunc, mPlotData.data(), mPlotData.size(), 0, 0, FLT_MAX, 0, 50u);

        widget.text("Presented surfel");
        widget.text(std::to_string(validSurfelCount) + " / " + std::to_string(kTotalSurfelLimit), true);
        widget.text("(" + std::to_string(validSurfelCount * 100.0f / kTotalSurfelLimit) + " %)", true);

        widget.text("Ray Budget");
        widget.text(std::to_string(requestedRayCount) + " / " + std::to_string(kRayBudget), true);
        widget.text("(" + std::to_string(requestedRayCount * 100.0f / kRayBudget) + " %)", true);

        widget.text("Cell containing surfel");
        widget.text(std::to_string(mpReadBackBuffer->getElement<uint>(3)), true);

        widget.text("Shortage");
        widget.text(std::to_string(mpReadBackBuffer->getElement<int>(2)), true);
    }

    widget.dummy("#spacer0", {1, 20});

    widget.slider("Target area size", configValue.surfelTargetArea, 200.0f, 4800.0f);
    widget.var("Cell unit", configValue.cellUnit, 0.005f, 0.1f);
    widget.slider("Per cell surfel limit", configValue.perCellSurfelLimit, 2u, 1024u);

    if (widget.button("Apply"))
        mApply = true;

    widget.dummy("#spacer0", {1, 20});

    widget.slider("Surfel visual radius", surfelVisualRadius, 0.0f, 1.0f);
    widget.checkbox("Direct Lighting (Surfel)", collectDirectLighting);
}

void SurfelGI::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    if (!mpScene)
        return;

    mFrameIndex = 0;
    mFrameDim = uint2(0, 0);
    mIsResourceDirty = true;
    mReadBackValid = false;
    mApply = false;
    mPlotData = std::vector<float>(1000, 0.f);

    createPasses();
    createBufferResources();
}

void SurfelGI::reflectInput(RenderPassReflection& reflector, uint2 resolution)
{
    reflector.addInput(kPackedHitInfoTextureName, "packed hit info texture")
        .format(ResourceFormat::RGBA32Uint)
        .bindFlags(ResourceBindFlags::ShaderResource);
}

void SurfelGI::reflectOutput(RenderPassReflection& reflector, uint2 resolution)
{
    reflector.addOutput(kOutputTextureName, "output texture")
        .format(ResourceFormat::RGBA32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);
}

void SurfelGI::createPasses()
{
    // Prepare Pass
    mpPreparePass = ComputePass::create(mpDevice, "RenderPasses/Surfel/SurfelGI/SurfelPreparePass.cs.slang", "csMain");

    // Update Pass (Collect Cell Info Pass)
    mpCollectCellInfoPass = ComputePass::create(
        mpDevice,
        "RenderPasses/Surfel/SurfelGI/SurfelUpdatePass.cs.slang",
        "collectCellInfo",
        mpScene->getSceneDefines()
    );

    // Update Pass (Accumulate Cell Info Pass)
    mpAccumulateCellInfoPass = ComputePass::create(
        mpDevice,
        "RenderPasses/Surfel/SurfelGI/SurfelUpdatePass.cs.slang",
        "accumulateCellInfo",
        mpScene->getSceneDefines()
    );

    // Update Pass (Update Cell To Surfel buffer Pass)
    mpUpdateCellToSurfelBuffer = ComputePass::create(
        mpDevice,
        "RenderPasses/Surfel/SurfelGI/SurfelUpdatePass.cs.slang",
        "updateCellToSurfelBuffer",
        mpScene->getSceneDefines()
    );

    // Surfel RayTrace Pass
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary("RenderPasses/Surfel/SurfelGI/SurfelRayTrace.rt.slang");
        desc.setMaxPayloadSize(72u);
        desc.setMaxAttributeSize(mpScene->getRaytracingMaxAttributeSize());
        desc.setMaxTraceRecursionDepth(2u);

        mRtPass.pBindingTable = RtBindingTable::create(2, 2, mpScene->getGeometryCount());
        mRtPass.pBindingTable->setRayGen(desc.addRayGen("rayGen"));
        mRtPass.pBindingTable->setMiss(0, desc.addMiss("scatterMiss"));
        mRtPass.pBindingTable->setMiss(1, desc.addMiss("shadowMiss"));

        mRtPass.pBindingTable->setHitGroup(
            0,
            mpScene->getGeometryIDs(Scene::GeometryType::TriangleMesh),
            desc.addHitGroup("scatterTriangleMeshClosestHit", "scatterTriangleMeshAnyHit")
        );

        mRtPass.pBindingTable->setHitGroup(
            1,
            mpScene->getGeometryIDs(Scene::GeometryType::TriangleMesh),
            desc.addHitGroup("", "shadowTriangleMeshAnyHit")
        );

        mRtPass.pProgram = Program::create(mpDevice, desc, mpScene->getSceneDefines());
        mRtPass.pProgram->addDefines(mpSampleGenerator->getDefines());
        mRtPass.pProgram->setTypeConformances(mpScene->getTypeConformances());

        mRtPass.pVars = RtProgramVars::create(mpDevice, mRtPass.pProgram, mRtPass.pBindingTable);
        mpSampleGenerator->bindShaderData(mRtPass.pVars->getRootVar());
    }

    // Surfel Generation Pass
    mpSurfelGenerationPass = ComputePass::create(
        mpDevice, "RenderPasses/Surfel/SurfelGI/SurfelGenerationPass.cs.slang", "csMain", mpScene->getSceneDefines()
    );

    // Surfel Integrate Pass
    mpSurfelIntegratePass = ComputePass::create(
        mpDevice, "RenderPasses/Surfel/SurfelGI/SurfelIntegratePass.cs.slang", "csMain", mpScene->getSceneDefines()
    );
}

void SurfelGI::createBufferResources()
{
    mpSurfelBuffer = mpDevice->createStructuredBuffer(
        sizeof(Surfel), kTotalSurfelLimit, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );

    mpSurfelValidIndexBuffer = mpDevice->createStructuredBuffer(
        sizeof(uint), kTotalSurfelLimit, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );

    mpSurfelDirtyIndexBuffer = mpDevice->createStructuredBuffer(
        sizeof(uint), kTotalSurfelLimit, ResourceBindFlags::ShaderResource, MemoryType::DeviceLocal, nullptr, false
    );

    {
        uint* freeIndexBuffer = new uint[kTotalSurfelLimit];
        std::iota(freeIndexBuffer, freeIndexBuffer + kTotalSurfelLimit, 0);

        mpSurfelFreeIndexBuffer = mpDevice->createStructuredBuffer(
            sizeof(uint),
            kTotalSurfelLimit,
            ResourceBindFlags::UnorderedAccess,
            MemoryType::DeviceLocal,
            freeIndexBuffer,
            false
        );

        delete[] freeIndexBuffer;
    }

    mpCellInfoBuffer = mpDevice->createStructuredBuffer(
        sizeof(CellInfo), kCellCount, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );

    mpCellToSurfelBuffer = mpDevice->createStructuredBuffer(
        sizeof(uint),
        kTotalSurfelLimit * 27,
        ResourceBindFlags::UnorderedAccess,
        MemoryType::DeviceLocal,
        nullptr,
        false
    );

    mpSurfelRayResultBuffer = mpDevice->createStructuredBuffer(
        sizeof(SurfelRayResult), kRayBudget, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );

    mpSurfelCounter = mpDevice->createBuffer(
        sizeof(uint) * _countof(kInitialStatus),
        ResourceBindFlags::UnorderedAccess,
        MemoryType::DeviceLocal,
        kInitialStatus
    );

    mpSurfelConfig = mpDevice->createBuffer(
        sizeof(SurfelConfig), ResourceBindFlags::ShaderResource, MemoryType::DeviceLocal, &configValue
    );

    mpReadBackBuffer = mpDevice->createBuffer(
        sizeof(uint) * _countof(kInitialStatus), ResourceBindFlags::None, MemoryType::ReadBack, nullptr
    );

    mpEmptySurfelBuffer = mpDevice->createStructuredBuffer(
        sizeof(Surfel), kTotalSurfelLimit, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );
}

void SurfelGI::createTextureResources() {}

void SurfelGI::bindResources(const RenderData& renderData)
{
    const auto& pPackedHitInfoTexture = renderData.getTexture(kPackedHitInfoTextureName);
    mpOutputTexture = renderData.getTexture(kOutputTextureName);

    // Prepare Pass
    {
        auto var = mpPreparePass->getRootVar();
        var[kSurfelCounterVarName] = mpSurfelCounter;
    }

    // Update Pass (Collect Cell Info Pass)
    {
        auto var = mpCollectCellInfoPass->getRootVar();

        var[kSurfelBufferVarName] = mpSurfelBuffer;
        var[kSurfelDirtyIndexBufferVarName] = mpSurfelDirtyIndexBuffer;
        var[kSurfelValidIndexBufferVarName] = mpSurfelValidIndexBuffer;
        var[kSurfelFreeIndexBufferVarName] = mpSurfelFreeIndexBuffer;
        var[kCellInfoBufferVarName] = mpCellInfoBuffer;

        var[kSurfelRayResultBufferVarName] = mpSurfelRayResultBuffer;

        var[kSurfelCounterVarName] = mpSurfelCounter;
        var[kSurfelConfigVarName] = mpSurfelConfig;
    }

    // Update Pass (Accumulate Cell Info Pass)
    {
        auto var = mpAccumulateCellInfoPass->getRootVar();

        var[kCellInfoBufferVarName] = mpCellInfoBuffer;
        var[kSurfelCounterVarName] = mpSurfelCounter;
    }

    // Update Pass (Update Cell To Surfel buffer Pass)
    {
        auto var = mpUpdateCellToSurfelBuffer->getRootVar();

        var[kSurfelBufferVarName] = mpSurfelBuffer;
        var[kSurfelValidIndexBufferVarName] = mpSurfelValidIndexBuffer;
        var[kCellInfoBufferVarName] = mpCellInfoBuffer;
        var[kCellToSurfelBufferVarName] = mpCellToSurfelBuffer;

        var[kSurfelCounterVarName] = mpSurfelCounter;
        var[kSurfelConfigVarName] = mpSurfelConfig;
    }

    // Surfel RayTrace Pass
    {
        auto var = mRtPass.pVars->getRootVar();

        var[kSurfelBufferVarName] = mpSurfelBuffer;
        var[kCellInfoBufferVarName] = mpCellInfoBuffer;
        var[kCellToSurfelBufferVarName] = mpCellToSurfelBuffer;

        var[kSurfelRayResultBufferVarName] = mpSurfelRayResultBuffer;

        var[kSurfelCounterVarName] = mpSurfelCounter;
    }

    // Surfel Generation Pass
    {
        auto var = mpSurfelGenerationPass->getRootVar();

        var[kSurfelBufferVarName] = mpSurfelBuffer;
        var[kSurfelFreeIndexBufferVarName] = mpSurfelFreeIndexBuffer;
        var[kSurfelValidIndexBufferVarName] = mpSurfelValidIndexBuffer;
        var[kCellInfoBufferVarName] = mpCellInfoBuffer;
        var[kCellToSurfelBufferVarName] = mpCellToSurfelBuffer;

        var[kSurfelCounterVarName] = mpSurfelCounter;
        var[kSurfelConfigVarName] = mpSurfelConfig;

        var["gPackedHitInfo"] = pPackedHitInfoTexture;
    }

    // Surfel Integrate Pass
    {
        auto var = mpSurfelIntegratePass->getRootVar();

        var[kSurfelBufferVarName] = mpSurfelBuffer;
        var[kCellInfoBufferVarName] = mpCellInfoBuffer;
        var[kCellToSurfelBufferVarName] = mpCellToSurfelBuffer;

        var[kSurfelRayResultBufferVarName] = mpSurfelRayResultBuffer;

        var[kSurfelConfigVarName] = mpSurfelConfig;

        var["gPackedHitInfo"] = pPackedHitInfoTexture;

        var["gOutput"] = mpOutputTexture;
    }
}
