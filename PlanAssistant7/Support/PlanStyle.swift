import SwiftUI

enum PlanStyle {
    static let appBackground = Color.black
    static let surface = Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
    static let surfaceStrong = Color(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
    static let border = Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255)
    static let textSecondary = Color.white.opacity(0.62)
    static let textMuted = Color.white.opacity(0.32)
    static let calendarBlue = Color(red: 10 / 255, green: 132 / 255, blue: 1)
    static let alarmOrange = Color(red: 1, green: 159 / 255, blue: 10 / 255)
    static let successGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let alertRed = Color(red: 1, green: 69 / 255, blue: 58 / 255)
}

struct PlanGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18
    var interactive = false
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(PlanStyle.surface.opacity(0.62), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(PlanStyle.border, lineWidth: 1)
                }
                .glassEffect(
                    interactive ? .regular.tint((tint ?? .clear).opacity(0.12)).interactive() : .regular.tint((tint ?? .clear).opacity(0.12)),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(PlanStyle.border, lineWidth: 1)
                }
        }
    }
}

extension View {
    func planGlassCard(cornerRadius: CGFloat = 18, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(PlanGlassCard(cornerRadius: cornerRadius, interactive: interactive, tint: tint))
    }
}

struct PlanEventKindIcon: View {
    var kind: EventKind
    var isAllDay = false
    var size: CGFloat = 34
    var cornerRadius: CGFloat = 10

    private var backgroundTint: Color {
        kind == .alarm ? PlanStyle.alarmOrange : PlanStyle.calendarBlue
    }

    private var mainIconName: String {
        if kind == .alarm {
            return "calendar"
        }
        return isAllDay ? "sun.max.fill" : "calendar"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(backgroundTint.opacity(0.16))

            Image(systemName: mainIconName)
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(PlanStyle.calendarBlue)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if kind == .alarm {
                alarmBadge
            }
        }
    }

    private var alarmBadge: some View {
        ZStack {
            Circle()
                .fill(PlanStyle.alarmOrange)
            Image(systemName: "alarm.fill")
                .font(.system(size: size * 0.22, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: size * 0.44, height: size * 0.44)
        .overlay {
            Circle()
                .stroke(PlanStyle.surface, lineWidth: max(size * 0.04, 1))
        }
    }
}

struct PlanPrimaryButtonStyle: ButtonStyle {
    var tint: Color = PlanStyle.calendarBlue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(tint.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct PlanSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(PlanStyle.surfaceStrong.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PlanStyle.border, lineWidth: 1)
            }
    }
}
