#include "RenderGraph/RenderPass.h"
#include "SurfelGBuffer/SurfelGBuffer.h"
#include "SurfelPreparePass/SurfelPreparePass.h"
#include "SurfelUpdatePass/SurfelUpdatePass.h"
#include "SurfelCoveragePass/SurfelCoveragePass.h"
#include "SurfelGenPass/SurfelGenPass.h"
#include "SurfelDebugPass/SurfelDebugPass.h"

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, SurfelGBuffer>();
    registry.registerClass<RenderPass, SurfelPreparePass>();
    registry.registerClass<RenderPass, SurfelUpdatePass>();
    registry.registerClass<RenderPass, SurfelCoveragePass>();
    registry.registerClass<RenderPass, SurfelGenPass>();
    registry.registerClass<RenderPass, SurfelDebugPass>();
}
