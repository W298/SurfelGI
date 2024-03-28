#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"
#include "../RenderPasses/Surfel/SurfelBase.h"

using namespace Falcor;

class SurfelCoveragePass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(SurfelCoveragePass, "SurfelCoveragePass", "Surfel coverage pass");

    static ref<SurfelCoveragePass> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<SurfelCoveragePass>(pDevice, props);
    }

    SurfelCoveragePass(ref<Device> pDevice, const Properties& props);

    virtual Properties getProperties() const override { return {}; }
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override {}
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override {}
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override { return false; }

private:
    void createSurfelBuffer(Dictionary& dict);

    ref<Scene> mpScene;
    ref<ComputePass> mpComputePass;
};
