#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"

using namespace Falcor;

class DirectIlluminationPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(DirectIlluminationPass, "DirectIlluminationPass", "Direct Illumination Pass");

    static ref<DirectIlluminationPass> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<DirectIlluminationPass>(pDevice, props);
    }

    DirectIlluminationPass(ref<Device> pDevice, const Properties& props);

    virtual Properties getProperties() const override;
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override;
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override { return false; }

private:
    ref<Scene> mpScene;
    ref<GraphicsState> mpState;
    ref<Program> mpProgram;
    ref<ProgramVars> mpVars;
    ref<Fbo> mpFbo;

    float4 mColor = float4(0, 1, 0, 1);

    ref<RasterizerState> mpRasterState;
};
