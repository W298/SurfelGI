#include "SurfelPreparePass.h"
#include "../RenderPasses/Surfel/SurfelTypes.hlsl"

SurfelPreparePass::SurfelPreparePass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");

    mpComputePass =
        ComputePass::create(mpDevice, "RenderPasses/Surfel/SurfelPreparePass/SurfelPreparePass.hlsl", "csMain");
}

RenderPassReflection SurfelPreparePass::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    // Empty

    return reflector;
}

void SurfelPreparePass::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    auto& dict = renderData.getDictionary();
    if (!dict.keyExists("surfelBuffer"))
        createSurfelBuffer(dict);
    if (!dict.keyExists("surfelStatus"))
        createSurfelStatus(dict);
    if (!dict.keyExists("cellInfoBuffer"))
        createCellInfoBuffer(dict);
    if (!dict.keyExists("cellToSurfelBuffer"))
        createCellToSurfelBuffer(dict);

    if (mpComputePass)
    {
        auto var = mpComputePass->getRootVar();

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");
        var["gSurfelStatus"] = dict.getValue<ref<Buffer>>("surfelStatus");
        var["gCellInfoBuffer"] = dict.getValue<ref<Buffer>>("cellInfoBuffer");
        var["gCellToSurfelBuffer"] = dict.getValue<ref<Buffer>>("cellToSurfelBuffer");

        mpComputePass->execute(pRenderContext, uint3(1));
    }
}

void SurfelPreparePass::createSurfelBuffer(Dictionary& dict)
{
    const ref<Buffer> surfelBuffer = mpDevice->createStructuredBuffer(
        sizeof(Surfel), kTotalSurfelLimit, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );
    dict["surfelBuffer"] = surfelBuffer;
}

void SurfelPreparePass::createSurfelStatus(Dictionary& dict)
{
    const ref<Buffer> surfelStatus = mpDevice->createBuffer(sizeof(uint) * 2);
    dict["surfelStatus"] = surfelStatus;
}

void SurfelPreparePass::createCellInfoBuffer(Dictionary& dict)
{
    const ref<Buffer> cellInfoBuffer = mpDevice->createStructuredBuffer(
        sizeof(CellInfo), kCellCount, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );
    dict["cellInfoBuffer"] = cellInfoBuffer;
}

void SurfelPreparePass::createCellToSurfelBuffer(Dictionary& dict)
{
    const ref<Buffer> cellToSurfelBuffer = mpDevice->createStructuredBuffer(
        sizeof(uint), kTotalSurfelLimit * 27, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    ); // #TODO
    dict["cellToSurfelBuffer"] = cellToSurfelBuffer;
}
