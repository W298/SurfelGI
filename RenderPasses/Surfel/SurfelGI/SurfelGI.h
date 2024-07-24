#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"
#include "RenderGraph/RenderPassHelpers.h"
#include "OverlayMode.slang"

using namespace Falcor;

class SurfelGI : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(SurfelGI, "SurfelGI", "Surfel GI Pass");

    static ref<SurfelGI> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<SurfelGI>(pDevice, props);
    }

    SurfelGI(ref<Device> pDevice, const Properties& props);

    virtual void setProperties(const Properties& props) override {}
    virtual Properties getProperties() const override { return {}; }
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override {}
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override;

private:
    void reflectInput(RenderPassReflection& reflector, uint2 resolution);
    void reflectOutput(RenderPassReflection& reflector, uint2 resolution);
    void resetAndRecompile();
    void createPasses();
    void createBufferResources();
    void createTextureResources();
    void bindResources(const RenderData& renderData);

    struct RuntimeParams
    {
        // Surfel generation.
        float chanceMultiply = 0.3f;
        uint chancePower = 1;
        float placementThreshold = 2.f;
        float removalThreshold = 4.f;
        float thresholdGap = 2.f;
        uint blendingDelay = 240;
        Falcor::OverlayMode overlayMode = Falcor::OverlayMode::IndirectLighting;

        // Ray tracing.
        uint rayStep = 3;
        uint maxStep = 6;

        // Integrate.
        float shortMeanWindow = 0.03f;
    };

    struct StaticParams
    {
        uint surfelTargetArea = 40000;
        float cellUnit = 0.05f;
        uint cellDim = 250u;
        uint cellCount = cellDim * cellDim * cellDim;
        uint perCellSurfelLimit = 1024u;

        bool useSurfelRadinace = true;
        bool limitSurfelSearch = false;
        uint maxSurfelForStep = 10;
        bool useRayGuiding = false;

        bool useIrradinaceSharing = false;

        DefineList getDefines(const SurfelGI& owner) const;
    };

    RuntimeParams mRuntimeParams;
    StaticParams mStaticParams;
    StaticParams mTempStaticParams;

    uint mFrameIndex;
    uint mMaxFrameIndex;
    uint2 mFrameDim;
    float mFOVy;
    float3 mCamPos;
    float mRenderScale;

    bool mIsResourceDirty;
    bool mReadBackValid;
    bool mLockSurfel;
    bool mResetSurfelBuffer;
    bool mRecompile;

    std::vector<float> mSurfelCount;
    std::vector<float> mRayBudget;

    ref<Scene> mpScene;
    ref<Fence> mpFence;
    ref<SampleGenerator> mpSampleGenerator;

    ref<ComputePass> mpSurfelEvaluationPass;

    ref<ComputePass> mpPreparePass;
    ref<ComputePass> mpCollectCellInfoPass;
    ref<ComputePass> mpAccumulateCellInfoPass;
    ref<ComputePass> mpUpdateCellToSurfelBuffer;
    ref<ComputePass> mpSurfelGenerationPass;
    ref<ComputePass> mpSurfelIntegratePass;

    struct
    {
        ref<Program> pProgram;
        ref<RtBindingTable> pBindingTable;
        ref<RtProgramVars> pVars;
    } mRtPass;

    ref<Texture> mpOutputTexture;
    ref<Texture> mpDebugTexture;
    ref<Texture> mpIrradianceMapTexture;

    ref<Buffer> mpSurfelBuffer;
    ref<Buffer> mpSurfelGeometryBuffer;
    ref<Buffer> mpSurfelValidIndexBuffer;
    ref<Buffer> mpSurfelDirtyIndexBuffer;
    ref<Buffer> mpSurfelFreeIndexBuffer;
    ref<Buffer> mpCellInfoBuffer;
    ref<Buffer> mpCellToSurfelBuffer;
    ref<Buffer> mpSurfelRayResultBuffer;
    ref<Buffer> mpSurfelRecycleInfoBuffer;

    ref<Buffer> mpSurfelReservationBuffer;
    ref<Buffer> mpSurfelRefCounter;
    ref<Buffer> mpSurfelCounter;

    ref<Buffer> mpEmptySurfelBuffer;
    ref<Buffer> mpReadBackBuffer;
};
