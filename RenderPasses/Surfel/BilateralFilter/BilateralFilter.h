#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"

using namespace Falcor;

class BilateralFilter : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(BilateralFilter, "BilateralFilter", "Bilateral Filter");

    static ref<BilateralFilter> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<BilateralFilter>(pDevice, props);
    }

    BilateralFilter(ref<Device> pDevice, const Properties& props);

    virtual Properties getProperties() const override { return {}; }
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override {}
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override { return false; }

private:
    ref<ComputeState>       mpState;
    ref<Program>            mpProgram;
    ref<ProgramVars>        mpVars;

    float                   mSigmaD;
    float                   mSigmaR;
};
