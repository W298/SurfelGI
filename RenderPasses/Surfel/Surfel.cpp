#include "RenderGraph/RenderPass.h"
#include "SurfelGBuffer/SurfelGBuffer.h"
#include "SurfelDirectLightingPass/SurfelDirectLightingPass.h"
#include "SurfelGI/SurfelGI.h"

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, SurfelGBuffer>();
    registry.registerClass<RenderPass, SurfelDirectLightingPass>();
    registry.registerClass<RenderPass, SurfelGI>();
}
