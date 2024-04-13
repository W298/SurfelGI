#pragma once
#include "Falcor.h"
#include "RenderGraph/RenderPass.h"
#include "SurfelTypes.hlsli"

using namespace Falcor;

namespace
{
const std::string kSurfelBufferDictName = "surfelBuffer";
const std::string kSurfelValidIndexBufferDictName = "surfelValidIndexBuffer";
const std::string kSurfelDirtyIndexBufferDictName = "surfelDirtyIndexBuffer";
const std::string kSurfelFreeIndexBufferDictName = "surfelFreeIndexBuffer";
const std::string kCellInfoBufferDictName = "cellInfoBuffer";
const std::string kCellToSurfelBufferDictName = "cellToSurfelBuffer";
const std::string kSurfelCounterDictName = "surfelCounter";
const std::string kSurfelConfigDictName = "surfelConfig";

const std::string kSurfelBufferVarName = "gSurfelBuffer";
const std::string kSurfelValidIndexBufferVarName = "gSurfelValidIndexBuffer";
const std::string kSurfelDirtyIndexBufferVarName = "gSurfelDirtyIndexBuffer";
const std::string kSurfelFreeIndexBufferVarName = "gSurfelFreeIndexBuffer";
const std::string kCellInfoBufferVarName = "gCellInfoBuffer";
const std::string kCellToSurfelBufferVarName = "gCellToSurfelBuffer";
const std::string kSurfelCounterVarName = "gSurfelCounter";
const std::string kSurfelConfigVarName = "gSurfelConfig";
} // namespace

static ref<Buffer> getSurfelBuffer(const ref<Device>& pDevice, Dictionary& dict)
{
    if (!dict.keyExists(kSurfelBufferDictName))
    {
        dict[kSurfelBufferDictName] = pDevice->createStructuredBuffer(
            sizeof(Surfel),
            kTotalSurfelLimit,
            ResourceBindFlags::UnorderedAccess,
            MemoryType::DeviceLocal,
            nullptr,
            false
        );
    }

    return dict.getValue<ref<Buffer>>(kSurfelBufferDictName);
}

static ref<Buffer> getSurfelValidIndexBuffer(const ref<Device>& pDevice, Dictionary& dict)
{
    if (!dict.keyExists(kSurfelValidIndexBufferDictName))
    {
        dict[kSurfelValidIndexBufferDictName] = pDevice->createStructuredBuffer(
            sizeof(uint), kTotalSurfelLimit, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
        );
    }

    return dict.getValue<ref<Buffer>>(kSurfelValidIndexBufferDictName);
}

static ref<Buffer> getSurfelDirtyIndexBuffer(const ref<Device>& pDevice, Dictionary& dict)
{
    if (!dict.keyExists(kSurfelDirtyIndexBufferDictName))
    {
        dict[kSurfelDirtyIndexBufferDictName] = pDevice->createStructuredBuffer(
            sizeof(uint), kTotalSurfelLimit, ResourceBindFlags::ShaderResource, MemoryType::DeviceLocal, nullptr, false
        );
    }

    return dict.getValue<ref<Buffer>>(kSurfelDirtyIndexBufferDictName);
}

static ref<Buffer> getSurfelFreeIndexBuffer(const ref<Device>& pDevice, Dictionary& dict)
{
    if (!dict.keyExists(kSurfelFreeIndexBufferDictName))
    {
        uint* freeIndexBuffer = new uint[kTotalSurfelLimit];
        std::iota(freeIndexBuffer, freeIndexBuffer + kTotalSurfelLimit, 0);

        dict[kSurfelFreeIndexBufferDictName] = pDevice->createStructuredBuffer(
            sizeof(uint),
            kTotalSurfelLimit,
            ResourceBindFlags::UnorderedAccess,
            MemoryType::DeviceLocal,
            freeIndexBuffer,
            false
        );

        delete[] freeIndexBuffer;
    }

    return dict.getValue<ref<Buffer>>(kSurfelFreeIndexBufferDictName);
}

static ref<Buffer> getCellInfoBuffer(const ref<Device>& pDevice, Dictionary& dict)
{
    if (!dict.keyExists(kCellInfoBufferDictName))
    {
        dict[kCellInfoBufferDictName] = pDevice->createStructuredBuffer(
            sizeof(CellInfo), kCellCount, ResourceBindFlags::UnorderedAccess, MemoryType::DeviceLocal, nullptr, false
        );
    }

    return dict.getValue<ref<Buffer>>(kCellInfoBufferDictName);
}

static ref<Buffer> getCellToSurfelBuffer(const ref<Device>& pDevice, Dictionary& dict)
{
    if (!dict.keyExists(kCellToSurfelBufferDictName))
    {
        dict[kCellToSurfelBufferDictName] = pDevice->createStructuredBuffer(
            sizeof(uint),
            kTotalSurfelLimit * 27,
            ResourceBindFlags::UnorderedAccess,
            MemoryType::DeviceLocal,
            nullptr,
            false
        );
    }

    return dict.getValue<ref<Buffer>>(kCellToSurfelBufferDictName);
}

static ref<Buffer> getSurfelCounter(const ref<Device>& pDevice, Dictionary& dict)
{
    if (!dict.keyExists(kSurfelCounterDictName))
    {
        dict[kSurfelCounterDictName] = pDevice->createBuffer(
            sizeof(uint) * _countof(kInitialStatus),
            ResourceBindFlags::UnorderedAccess,
            MemoryType::DeviceLocal,
            kInitialStatus
        );
    }

    return dict.getValue<ref<Buffer>>(kSurfelCounterDictName);
}

static ref<Buffer> getSurfelConfig(const ref<Device>& pDevice, Dictionary& dict)
{
    if (!dict.keyExists(kSurfelConfigDictName))
    {
        const SurfelConfig initData = SurfelConfig();
        dict[kSurfelConfigDictName] = pDevice->createBuffer(
            sizeof(SurfelConfig), ResourceBindFlags::ShaderResource, MemoryType::DeviceLocal, &initData
        );
    }

    return dict.getValue<ref<Buffer>>(kSurfelConfigDictName);
}
