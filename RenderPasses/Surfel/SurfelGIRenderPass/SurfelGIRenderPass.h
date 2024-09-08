#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"

using namespace Falcor;

class SurfelGIRenderPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(SurfelGIRenderPass, "SurfelGIRenderPass", "Calculate direct lighting and integrate with input indirect lighting");

    static ref<SurfelGIRenderPass> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<SurfelGIRenderPass>(pDevice, props);
    }

    SurfelGIRenderPass(ref<Device> pDevice, const Properties& props);

    virtual Properties getProperties() const override { return {}; }
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override {}
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override { return false; }

private:
    ref<Scene>              mpScene;
    ref<SampleGenerator>    mpSampleGenerator;

    ref<ComputePass>        mpLightingPass;
    ref<ComputePass>        mpBlurringPass;
    ref<ComputePass>        mpIntegratePass;

    uint                    mFrameIndex;
    bool                    mRenderDirectLighting;
    bool                    mRenderIndirectLighting;
    bool                    mRenderReflection;
    float                   mSigmaD;
    float                   mSigmaR;
};
