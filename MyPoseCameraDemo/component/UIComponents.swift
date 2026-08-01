//
//  UIComponents.swift
//  MtPoseCameraDemo26
//
//  Shared UI building blocks: card style, button styles, section headers.
//

import SwiftUI

// MARK: - Card container

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 3)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardBackground())
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let icon: String
    let title: String
    var tint: Color = .primary
    var trailing: (() -> AnyView)? = nil
    
    init(_ icon: String, _ title: String, tint: Color = .primary) {
        self.icon = icon
        self.title = title
        self.tint = tint
    }
    
    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Spacer()
        }
    }
}

// MARK: - Primary filled button style

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = .accentColor
    var isDisabled: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDisabled ? color.opacity(0.35) : color)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static func primary(_ color: Color = .accentColor, disabled: Bool = false) -> PrimaryButtonStyle {
        PrimaryButtonStyle(color: color, isDisabled: disabled)
    }
}

// MARK: - Metadata row (label / value)

struct MetadataRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Empty state placeholder

struct EmptyStatePlaceholder: View {
    let icon: String
    let text: String
    var height: CGFloat = 160
    
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
            .frame(height: height)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            )
    }
}

// MARK: - Toast

struct ToastView: View {
    let icon: String
    let text: String
    var color: Color = .green
    
    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(color)
            )
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Pill badge (small colored tag)

struct PillBadge: View {
    let text: String
    var color: Color = .accentColor
    
    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}
