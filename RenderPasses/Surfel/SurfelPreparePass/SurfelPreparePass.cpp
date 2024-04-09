#include "SurfelPreparePass.h"
#include "../RenderPasses/Surfel/SurfelTypes.hlsli"

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
    if (!dict.keyExists("surfelFreeIndexBuffer"))
        createSurfelFreeIndexBuffer(dict);
    if (!dict.keyExists("surfelValidIndexBuffer"))
        createSurfelValidIndexBuffer(dict);
    if (!dict.keyExists("surfelCounter"))
        createSurfelCounter(dict);
    if (!dict.keyExists("cellInfoBuffer"))
        createCellInfoBuffer(dict);
    if (!dict.keyExists("cellToSurfelBuffer"))
        createCellToSurfelBuffer(dict);

    if (mpComputePass)
    {
        auto var = mpComputePass->getRootVar();

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");
        var["gSurfelCounter"] = dict.getValue<ref<Buffer>>("surfelCounter");
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

void SurfelPreparePass::createSurfelFreeIndexBuffer(Dictionary& dict)
{
    uint freeIndexBuffer[kTotalSurfelLimit];
    std::iota(std::begin(freeIndexBuffer), std::end(freeIndexBuffer), 0);

    const ref<Buffer> surfelFreeIndexBuffer = mpDevice->createStructuredBuffer(
        sizeof(uint), kTotalSurfelLimit, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, freeIndexBuffer, false
    );
    dict["surfelFreeIndexBuffer"] = surfelFreeIndexBuffer;
}

void SurfelPreparePass::createSurfelValidIndexBuffer(Dictionary& dict)
{
    const ref<Buffer> surfelValidIndexBuffer = mpDevice->createStructuredBuffer(
        sizeof(uint), kTotalSurfelLimit, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );
    dict["surfelValidIndexBuffer"] = surfelValidIndexBuffer;
}

void SurfelPreparePass::createSurfelCounter(Dictionary& dict)
{
    const ref<Buffer> surfelCounter = mpDevice->createBuffer(
        sizeof(uint) * _countof(kInitialStatus),
        ResourceBindFlags::UnorderedAccess,
        MemoryType::DeviceLocal,
        kInitialStatus
    );
    dict["surfelCounter"] = surfelCounter;
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
        sizeof(uint),
        kTotalSurfelLimit * kPerCellSurfelLimit * 27,
        ResourceBindFlags::UnorderedAccess,
        MemoryType::DeviceLocal,
        nullptr,
        false
    );
    dict["cellToSurfelBuffer"] = cellToSurfelBuffer;
}
