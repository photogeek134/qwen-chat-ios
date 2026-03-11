import SwiftUI

/// Shown above the input bar whenever the last generation was cut off
/// at the token limit rather than finishing naturally at an EOS token.
/// Tapping “Continue” calls viewModel.continueGeneration().
struct ContinueBanner: View {
let tokenBudget: Int
let onContinue: () -> Void
let onDismiss: () -> Void

```
var body: some View {
    HStack(spacing: 10) {
        Image(systemName: "text.append")
            .foregroundStyle(.orange)

        VStack(alignment: .leading, spacing: 1) {
            Text("Response was cut off")
                .font(.subheadline.weight(.medium))
            Text("Reached the \(tokenBudget)-token limit for this device")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Spacer()

        Button(action: onContinue) {
            Text("Continue")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.15), in: Capsule())
                .foregroundStyle(.orange)
        }

        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Color.orange.opacity(0.08))
    .overlay(alignment: .bottom) {
        Divider()
    }
    .transition(.move(edge: .bottom).combined(with: .opacity))
}
```

}

#Preview {
ContinueBanner(tokenBudget: 4096, onContinue: {}, onDismiss: {})
}