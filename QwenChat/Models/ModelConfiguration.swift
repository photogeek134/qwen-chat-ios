import Foundation

// MARK: - Device Memory Helper

/// Reads the device’s physical RAM via ProcessInfo and rounds to the
/// nearest 256 MB boundary (iOS always ships with power-of-two RAM).
enum DeviceMemory {
/// Total physical RAM in bytes.
static let totalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory


/// Total physical RAM in gigabytes (floating point for comparisons).
static let totalGB: Double = Double(totalBytes) / 1_073_741_824.0

/// Rounded GB value snapped to the nearest 256 MB step.
/// e.g. 5.93 GB physical → 6 GB bucket.
static let bucketGB: Double = {
    let mb = Double(totalBytes) / 1_048_576.0          // bytes → MB
    let rounded = (mb / 256.0).rounded() * 256.0       // snap to 256 MB
    return rounded / 1024.0                             // MB → GB
}()


}

// MARK: - Model Catalogue

/// All Qwen 3.5 variants the app can offer.
/// Each case knows its own memory requirement and whether the current
/// device has enough RAM to run it safely.
enum QwenModel: String, CaseIterable, Identifiable {


case qwen35_0_8B = "qwen35_0_8b"
case qwen35_2B   = "qwen35_2b"
case qwen35_4B   = "qwen35_4b"
case qwen35_9B   = "qwen35_9b"

var id: String { rawValue }

// MARK: - Display

var displayName: String {
    switch self {
    case .qwen35_0_8B: return "Qwen 3.5 0.8B"
    case .qwen35_2B:   return "Qwen 3.5 2B"
    case .qwen35_4B:   return "Qwen 3.5 4B"
    case .qwen35_9B:   return "Qwen 3.5 9B"
    }
}

var approximateSizeDescription: String {
    switch self {
    case .qwen35_0_8B: return "~0.6 GB"
    case .qwen35_2B:   return "~1.4 GB"
    case .qwen35_4B:   return "~2.5 GB"
    case .qwen35_9B:   return "~5.6 GB"
    }
}

// MARK: - Memory requirements

/// Model weights on disk / in unified memory at 4-bit quantisation.
var modelWeightGB: Double {
    switch self {
    case .qwen35_0_8B: return 0.6
    case .qwen35_2B:   return 1.4
    case .qwen35_4B:   return 2.5
    case .qwen35_9B:   return 5.6
    }
}

/// Minimum physical RAM (in GB) required for stable operation.
/// Formula: weights × ~1.5 headroom factor covering KV-cache,
/// vision encoder, OS overhead, and mlx-swift-lm load-time usage.
var minimumDeviceRAMGB: Double {
    switch self {
    case .qwen35_0_8B: return 4.0   // fine on any modern iPhone (6 GB+)
    case .qwen35_2B:   return 6.0   // iPhone 14+ / any iPad
    case .qwen35_4B:   return 8.0   // iPhone 15 Pro+ / iPad with ≥8 GB
    case .qwen35_9B:   return 10.0  // iPad Pro M4/M5 (12-16 GB)
    }
}

/// Whether this model is runnable on the current device.
var isSupported: Bool {
    DeviceMemory.bucketGB >= minimumDeviceRAMGB
}

/// Human-readable reason shown in a disabled picker row.
var unsupportedReason: String {
    let needed = Int(minimumDeviceRAMGB)
    let have   = Int(DeviceMemory.bucketGB.rounded())
    return "Requires ≥\(needed) GB RAM (device has ~\(have) GB)"
}


var supportsVision: Bool { true }

// MARK: - HuggingFace model IDs

var huggingFaceID: String {
    switch self {
    case .qwen35_0_8B: return "mlx-community/Qwen3.5-0.8B-MLX-4bit"
    case .qwen35_2B:   return "mlx-community/Qwen3.5-2B-MLX-4bit"
    case .qwen35_4B:   return "mlx-community/Qwen3.5-4B-MLX-4bit"
    case .qwen35_9B:   return "mlx-community/Qwen3.5-9B-MLX-4bit"
    }
}

// MARK: - Convenience

/// All models that can run on this device, in ascending parameter order.
static var supportedModels: [QwenModel] {
    allCases.filter { $0.isSupported }
}

/// The best (largest) supported model; falls back to 0.8B if somehow
/// nothing passes the gate (e.g. very low-RAM simulator).
static var defaultModel: QwenModel {
    supportedModels.last ?? .qwen35_0_8B
}


}
