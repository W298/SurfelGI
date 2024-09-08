#include "RenderGraph/RenderPass.h"
#include "SurfelGBuffer/SurfelGBuffer.h"
#include "SurfelVBuffer/SurfelVBuffer.h"
#include "SurfelGIRenderPass/SurfelGIRenderPass.h"
#include "SurfelGI/SurfelGI.h"
#include "BilateralFilter/BilateralFilter.h"

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, SurfelGBuffer>();
    registry.registerClass<RenderPass, SurfelVBuffer>();
    registry.registerClass<RenderPass, SurfelGIRenderPass>();
    registry.registerClass<RenderPass, SurfelGI>();
    registry.registerClass<RenderPass, BilateralFilter>();
}
