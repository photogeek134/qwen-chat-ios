import Foundation
import MLXLMCommon

enum AppModel: String, CaseIterable, Identifiable {
  case qwen3_5_0_8B = "Qwen3.5 0.8B"
  case qwen3_5_2B   = "Qwen3.5 2B"
  case qwen3_5_4B   = "Qwen3.5 4B"
  case qwen3_5_9B   = "Qwen3.5 9B"

  var id: String { rawValue }
  var displayName: String { rawValue }

  var huggingFaceID: String {
    switch self {
    case .qwen3_5_0_8B:
      return "mlx-community/Qwen3.5-0.8B-4bit"
    case .qwen3_5_2B:
      return "mlx-community/Qwen3.5-2B-4bit"
    case .qwen3_5_4B:
      return "mlx-community/Qwen3.5-4B-MLX-4bit"
    case .qwen3_5_9B:
      return "mlx-community/Qwen3.5-9B-MLX-4bit"
    }
  }

  /// These are vision-language models (Image-Text-to-Text) with vision support.
  var isVisionModel: Bool { true }

  var modelConfiguration: ModelConfiguration {
    ModelConfiguration(id: huggingFaceID)
  }
}
