#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"
#include "RenderGraph/RenderPassHelpers.h"

using namespace Falcor;

class SurfelDebugPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(SurfelDebugPass, "SurfelDebugPass", "Surfel Debug Pass");

    static ref<SurfelDebugPass> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<SurfelDebugPass>(pDevice, props);
    }

    SurfelDebugPass(ref<Device> pDevice, const Properties& props);

    virtual Properties getProperties() const override { return {}; }
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override {}
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override {}
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override { return false; }

private:
    ref<Scene> mpScene;
    ref<GraphicsState> mpState;
    ref<RasterizerState> mpRasterState;
    ref<Program> mpProgram;
    ref<ProgramVars> mpVars;
    ref<Fbo> mpFbo;
};
