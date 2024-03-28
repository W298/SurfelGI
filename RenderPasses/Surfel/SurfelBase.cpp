#include "RenderGraph/RenderPass.h"
#include "SurfelCoveragePass/SurfelCoveragePass.h"
#include "SurfelGenPass/SurfelGenPass.h"

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, SurfelCoveragePass>();
    registry.registerClass<RenderPass, SurfelGenPass>();
}
