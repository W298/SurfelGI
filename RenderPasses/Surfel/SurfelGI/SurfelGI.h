#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"

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
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override { return false; }

private:
    void reflectInput(RenderPassReflection& reflector, uint2 resolution);
    void reflectOutput(RenderPassReflection& reflector, uint2 resolution);

    void createPasses();

    void createBufferResources();
    void createTextureResources();

    void bindResources(const RenderData& renderData);

    uint mFrameIndex;
    uint2 mFrameDim;
    float mFOVy;
    float3 mCamPos;
    float4x4 mInvViewProj;

    bool mIsResourceDirty;
    bool mReadBackValid;
    bool mApply;

    std::vector<float> mPlotData;

    ref<Scene> mpScene;
    ref<Fence> mpFence;
    ref<SampleGenerator> mpSampleGenerator;

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

    ref<Buffer> mpSurfelBuffer;
    ref<Buffer> mpSurfelValidIndexBuffer;
    ref<Buffer> mpSurfelDirtyIndexBuffer;
    ref<Buffer> mpSurfelFreeIndexBuffer;
    ref<Buffer> mpCellInfoBuffer;
    ref<Buffer> mpCellToSurfelBuffer;

    ref<Buffer> mpSurfelRayResultBuffer;

    ref<Buffer> mpSurfelCounter;
    ref<Buffer> mpSurfelConfig;

    ref<Buffer> mpEmptySurfelBuffer;
    ref<Buffer> mpReadBackBuffer;
};
