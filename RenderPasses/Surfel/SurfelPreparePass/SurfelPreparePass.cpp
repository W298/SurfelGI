#include "SurfelPreparePass.h"

SurfelPreparePass::SurfelPreparePass(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check device feature support.
    mpDevice = pDevice;
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_5))
        FALCOR_THROW("SceneDebugger requires Shader Model 6.5 support.");
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
    if (!dict.keyExists("cellIndexBuffer"))
        createCellIndexBuffer(dict);

    if (mpComputePass)
    {
        auto var = mpComputePass->getRootVar();

        var["gSurfelBuffer"] = dict.getValue<ref<Buffer>>("surfelBuffer");
        var["gSurfelStatus"] = dict.getValue<ref<Buffer>>("surfelStatus");
        var["gCellInfoBuffer"] = dict.getValue<ref<Buffer>>("cellInfoBuffer");
        var["gCellIndexBuffer"] = dict.getValue<ref<Buffer>>("cellIndexBuffer");

        mpComputePass->execute(pRenderContext, uint3(1, 1, 1));
    }
}

void SurfelPreparePass::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;

    if (mpScene)
    {
        mpComputePass = ComputePass::create(
            mpDevice,
            "RenderPasses/Surfel/SurfelPreparePass/SurfelPreparePass.cs.slang",
            "csMain",
            mpScene->getSceneDefines()
        );
    }
}

void SurfelPreparePass::createSurfelBuffer(Dictionary& dict)
{
    const ref<Buffer> surfelBuffer = mpDevice->createStructuredBuffer(
        sizeof(Surfel), kSurfelLimit, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );
    dict["surfelBuffer"] = surfelBuffer;
}

void SurfelPreparePass::createSurfelStatus(Dictionary& dict)
{
    const ref<Buffer> surfelStatus = mpDevice->createBuffer(sizeof(uint32_t) * 2);
    dict["surfelStatus"] = surfelStatus;
}

void SurfelPreparePass::createCellInfoBuffer(Dictionary& dict)
{
    const ref<Buffer> cellInfoBuffer = mpDevice->createStructuredBuffer(
        sizeof(CellInfo), kCellCount, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );
    dict["cellInfoBuffer"] = cellInfoBuffer;
}

void SurfelPreparePass::createCellIndexBuffer(Dictionary& dict)
{
    const ref<Buffer> cellIndexBuffer = mpDevice->createStructuredBuffer(
        sizeof(uint32_t), kSurfelLimit * 27, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
    );
    dict["cellIndexBuffer"] = cellIndexBuffer;
}
