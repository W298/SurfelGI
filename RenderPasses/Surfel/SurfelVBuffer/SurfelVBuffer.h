#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"
#include "RenderGraph/RenderPassHelpers.h"

using namespace Falcor;

class SurfelVBuffer : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(SurfelVBuffer, "SurfelVBuffer", "Surfel VBuffer");

    static ref<SurfelVBuffer> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<SurfelVBuffer>(pDevice, props);
    }

    SurfelVBuffer(ref<Device> pDevice, const Properties& props);

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
    ref<SampleGenerator> mpSampleGenerator;

    uint2 mFrameDim;

    struct
    {
        ref<Program> pProgram;
        ref<RtBindingTable> pBindingTable;
        ref<RtProgramVars> pVars;
    } mRtPass;
};
