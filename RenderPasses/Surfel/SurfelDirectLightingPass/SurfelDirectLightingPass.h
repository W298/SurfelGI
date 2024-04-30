#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"

using namespace Falcor;

class SurfelDirectLightingPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(SurfelDirectLightingPass, "SurfelDirectLightingPass", "Direct lighting pass for SurfelGI");

    static ref<SurfelDirectLightingPass> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<SurfelDirectLightingPass>(pDevice, props);
    }

    SurfelDirectLightingPass(ref<Device> pDevice, const Properties& props);

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
    ref<ComputeState>       mpState;
    ref<Program>            mpProgram;
    ref<ProgramVars>        mpVars;

    ref<SampleGenerator>    mpSampleGenerator;

    uint                    mFrameIndex;
    bool                    mUseIndirectLighting;
};
