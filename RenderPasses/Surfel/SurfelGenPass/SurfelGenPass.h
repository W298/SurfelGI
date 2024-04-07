#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"

using namespace Falcor;

class SurfelGenPass : public RenderPass
{
public:
    FALCOR_PLUGIN_CLASS(SurfelGenPass, "SurfelGenPass", "Surfel gneration pass");

    static ref<SurfelGenPass> create(ref<Device> pDevice, const Properties& props)
    {
        return make_ref<SurfelGenPass>(pDevice, props);
    }

    SurfelGenPass(ref<Device> pDevice, const Properties& props);

    virtual Properties getProperties() const override { return {}; }
    virtual RenderPassReflection reflect(const CompileData& compileData) override;
    virtual void compile(RenderContext* pRenderContext, const CompileData& compileData) override {}
    virtual void execute(RenderContext* pRenderContext, const RenderData& renderData) override;
    virtual void renderUI(Gui::Widgets& widget) override;
    virtual void setScene(RenderContext* pRenderContext, const ref<Scene>& pScene) override;
    virtual bool onMouseEvent(const MouseEvent& mouseEvent) override { return false; }
    virtual bool onKeyEvent(const KeyboardEvent& keyEvent) override;

private:
    ref<Scene> mpScene;
    ref<ComputePass> mpComputePass;
    uint mFrameIndex;
    uint mNumSurfels;

    std::unordered_map<Input::Key, bool> mMovement;
    bool mIsMoving;
};
