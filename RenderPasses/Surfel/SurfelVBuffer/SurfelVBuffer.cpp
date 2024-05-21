#include "SurfelVBuffer.h"

SurfelVBuffer::SurfelVBuffer(ref<Device> pDevice, const Properties& props) : RenderPass(pDevice)
{
    // Check for required features.
    if (!mpDevice->isShaderModelSupported(ShaderModel::SM6_2))
        FALCOR_THROW("requires Shader Model 6.2 support.");
    if (!mpDevice->isFeatureSupported(Device::SupportedFeatures::Barycentrics))
        FALCOR_THROW("requires pixel shader barycentrics support.");
    if (!mpDevice->isFeatureSupported(Device::SupportedFeatures::RasterizerOrderedViews))
        FALCOR_THROW("requires rasterizer ordered views (ROVs) support.");

    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_UNIFORM);
}

RenderPassReflection SurfelVBuffer::reflect(const CompileData& compileData)
{
    RenderPassReflection reflector;

    reflector.addOutput("packedHitInfo", "Packed Hit Info")
        .format(ResourceFormat::RGBA32Uint)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    reflector.addOutput("depth", "Depth buffer")
        .format(ResourceFormat::R32Float)
        .bindFlags(ResourceBindFlags::UnorderedAccess);

    if (math::any(mFrameDim != compileData.defaultTexDims))
        mFrameDim = compileData.defaultTexDims;

    return reflector;
}

void SurfelVBuffer::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    if (!mpScene)
        return;

    auto var = mRtPass.pVars->getRootVar();

    var["CB"]["gResolution"] = mFrameDim;

    var["gPackedHitInfo"] = renderData.getTexture("packedHitInfo");
    var["gDepth"] = renderData.getTexture("depth");

    mpScene->raytrace(pRenderContext, mRtPass.pProgram.get(), mRtPass.pVars, uint3(mFrameDim, 1));
}

void SurfelVBuffer::setScene(RenderContext* pRenderContext, const ref<Scene>& pScene)
{
    mpScene = pScene;
    mFrameDim = uint2(0, 0);

    if (mpScene)
    {
        ProgramDesc desc;
        desc.addShaderModules(mpScene->getShaderModules());
        desc.addShaderLibrary("RenderPasses/Surfel/SurfelVBuffer/SurfelVBuffer.rt.slang");
        desc.setMaxPayloadSize(72u);
        desc.setMaxAttributeSize(mpScene->getRaytracingMaxAttributeSize());
        desc.setMaxTraceRecursionDepth(2u);

        mRtPass.pBindingTable = RtBindingTable::create(1, 1, mpScene->getGeometryCount());
        mRtPass.pBindingTable->setRayGen(desc.addRayGen("rayGen"));
        mRtPass.pBindingTable->setMiss(0, desc.addMiss("miss"));
        mRtPass.pBindingTable->setHitGroup(
            0, mpScene->getGeometryIDs(Scene::GeometryType::TriangleMesh), desc.addHitGroup("closeHit", "anyHit")
        );

        mRtPass.pProgram = Program::create(mpDevice, desc, mpScene->getSceneDefines());
        mRtPass.pProgram->addDefines(mpSampleGenerator->getDefines());
        mRtPass.pProgram->setTypeConformances(mpScene->getTypeConformances());

        mRtPass.pVars = RtProgramVars::create(mpDevice, mRtPass.pProgram, mRtPass.pBindingTable);
        mpSampleGenerator->bindShaderData(mRtPass.pVars->getRootVar());
    }
}
