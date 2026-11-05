import SwiftUI

/// Ten-band equalizer with the presets from the shared catalogue.
struct EqualizerScreen: View {
    @EnvironmentObject private var equalizer: EqualizerService
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Toggle(
                        isOn: Binding(
                            get: { equalizer.enabled },
                            set: { equalizer.setEnabled($0) }
                        )
                    ) {
                        Text("Эквалайзер включён")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(palette.textPrimary)
                    }
                    .tint(palette.textPrimary)

                    Hairline()

                    presets

                    Hairline()

                    bands
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.xxl)
            }
        }
        .background(palette.window)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Звук")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.textTertiary)
                Text("Эквалайзер")
                    .font(.title2.bold())
                    .foregroundStyle(palette.textPrimary)
            }

            Spacer()

            CircleIconButton(systemName: "xmark", size: 12, help: "Закрыть") {
                dismiss()
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .padding(.bottom, Space.m)
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.l) {
                ForEach(EqualizerCatalog.presets) { preset in
                    FilterChip(
                        title: preset.label,
                        isSelected: equalizer.presetID == preset.id
                    ) {
                        equalizer.applyPreset(preset.id)
                    }
                }
            }
            .padding(.vertical, Space.xs)
        }
    }

    private var bands: some View {
        VStack(spacing: Space.xs) {
            ForEach(0..<EqualizerCatalog.bandCount, id: \.self) { index in
                bandRow(index)
            }

            Button {
                equalizer.resetFlat()
            } label: {
                Text("Сбросить к плоскому")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .strokeBorder(palette.separatorStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, Space.m)
        }
    }

    private func bandRow(_ index: Int) -> some View {
        let gain = equalizer.gains.indices.contains(index) ? equalizer.gains[index] : 0

        return HStack(spacing: Space.m) {
            Text(EqualizerCatalog.label(forHz: EqualizerCatalog.frequencies[index]))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(palette.textTertiary)
                .frame(width: 34, alignment: .leading)

            Slider(
                value: Binding(
                    get: { gain },
                    set: { equalizer.setBand(index, value: $0) }
                ),
                in: EqualizerCatalog.minGain...EqualizerCatalog.maxGain,
                step: 1
            )
            .tint(palette.textPrimary)

            Text(String(format: "%+.0f", gain))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(
                    abs(gain) < 0.5 ? palette.textTertiary : palette.textPrimary
                )
                .frame(width: 40, alignment: .trailing)
        }
        .frame(height: 40)
        .opacity(equalizer.enabled ? 1 : 0.55)
    }
}
