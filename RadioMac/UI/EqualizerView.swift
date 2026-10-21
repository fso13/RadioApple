import SwiftUI

/// Equalizer sheet: one switch, text presets and ten vertical faders.
struct EqualizerView: View {
    @ObservedObject var equalizer: EqualizerService
    let onClose: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .top) {
                PageHeading(
                    title: "Эквалайзер",
                    subtitle: equalizer.isSupported
                        ? "10 полос · пресеты и своя кривая"
                        : "Плагин BASS_FX не загрузился"
                )
                Spacer()
                CircleIconButton(systemName: "xmark", size: 11, help: "Закрыть", action: onClose)
            }

            ToggleRow(
                title: "Включить",
                subtitle: equalizerSubtitle,
                isOn: equalizer.isSupported && equalizer.enabled,
                isEnabled: equalizer.isSupported,
                onChange: equalizer.setEnabled
            )

            Hairline()

            if !equalizer.isSupported {
                Text("Аудиоплагин не загрузился — коррекция недоступна. Настройки сохранятся.")
                    .font(Typeface.caption)
                    .foregroundStyle(palette.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            presets

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<EqualizerCatalog.bandCount, id: \.self) { index in
                    BandFader(
                        label: EqualizerCatalog.label(forHz: EqualizerCatalog.frequencies[index]),
                        value: equalizer.gains[index],
                        isEnabled: equalizer.enabled && equalizer.isSupported
                    ) { value in
                        equalizer.setBand(index, value: value)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 200)
            .opacity(equalizer.enabled && equalizer.isSupported ? 1 : 0.45)
            .allowsHitTesting(equalizer.enabled && equalizer.isSupported)

            Spacer(minLength: 0)

            HStack {
                TextButton(title: "Сбросить", systemImage: "arrow.counterclockwise") {
                    equalizer.resetFlat()
                }
                Spacer()
                PrimaryButton(title: "Готово", action: onClose)
            }
        }
        .padding(Space.xxl + 2)
        .frame(width: 560, height: 600)
        .background(palette.surface)
    }

    private var presets: some View {
        FlowLayout(spacing: Space.l, lineSpacing: Space.s) {
            ForEach(EqualizerCatalog.presets) { preset in
                let isSelected = equalizer.presetID == preset.id

                Button {
                    equalizer.applyPreset(preset.id)
                } label: {
                    VStack(spacing: 3) {
                        Text(preset.label)
                            .font(isSelected ? Typeface.captionMedium : Typeface.caption)
                            .foregroundStyle(isSelected ? palette.textPrimary : palette.textTertiary)
                        Rectangle()
                            .fill(isSelected ? palette.textPrimary : Color.clear)
                            .frame(height: 1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(equalizer.isSupported ? 1 : 0.45)
                .allowsHitTesting(equalizer.isSupported)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var equalizerSubtitle: String {
        guard equalizer.isSupported else { return "Недоступно на этом Mac" }
        return equalizer.enabled
            ? "10 полос · \(equalizer.preset.label)"
            : "Поток идёт без коррекции"
    }
}

/// Vertical fader for one EQ band, drawn as a thin ink line.
struct BandFader: View {
    let label: String
    let value: Double
    let isEnabled: Bool
    let onChange: (Double) -> Void

    @Environment(\.palette) private var palette

    private var displayValue: String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    var body: some View {
        VStack(spacing: Space.s) {
            Text(displayValue)
                .font(Typeface.monoSmall)
                .foregroundStyle(abs(value) < 0.5 ? palette.textTertiary : palette.textPrimary)
                .monospacedDigit()

            GeometryReader { geometry in
                let height = max(geometry.size.height, 1)
                let centerX = geometry.size.width / 2
                let zeroY = height / 2
                let knobY = yPosition(for: value, height: height)

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(palette.separator)
                        .frame(width: 2, height: height)
                        .position(x: centerX, y: zeroY)

                    Rectangle()
                        .fill(palette.textPrimary.opacity(0.9))
                        .frame(width: 2, height: max(abs(zeroY - knobY), 1))
                        .position(x: centerX, y: (zeroY + knobY) / 2)

                    Rectangle()
                        .fill(palette.separatorStrong)
                        .frame(width: 12, height: 1)
                        .position(x: centerX, y: zeroY)

                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(palette.textPrimary)
                        .frame(width: 16, height: 4)
                        .position(x: centerX, y: knobY)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            guard isEnabled else { return }
                            let ratio = min(1, max(0, gesture.location.y / height))
                            let next = EqualizerCatalog.maxGain
                                - ratio * (EqualizerCatalog.maxGain - EqualizerCatalog.minGain)
                            onChange(next)
                        }
                )
            }

            Text(label)
                .font(Typeface.monoSmall)
                .foregroundStyle(palette.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) герц")
        .accessibilityValue(displayValue + " децибел")
    }

    private func yPosition(for gain: Double, height: CGFloat) -> CGFloat {
        let span = EqualizerCatalog.maxGain - EqualizerCatalog.minGain
        let ratio = (EqualizerCatalog.maxGain - gain) / span
        return CGFloat(ratio) * height
    }
}
