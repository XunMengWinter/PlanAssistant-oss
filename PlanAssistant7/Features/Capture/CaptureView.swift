import SwiftUI

struct CaptureView: View {
    @Environment(SpeechTranscriber.self) private var speechTranscriber

    var onParseRequest: (String) -> Void

    @State private var inputText = ""
    @State private var ignoreTranscriptUpdates = false
    @State private var isPressingMic = false

    private var canSend: Bool {
        !inputText.trimmedPlanText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            Spacer(minLength: 8)

            voiceFocus
                .frame(maxWidth: .infinity)

            Spacer(minLength: 8)

            inputComposer
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .onChange(of: speechTranscriber.transcript) { _, newValue in
            guard !ignoreTranscriptUpdates, !newValue.isEmpty else { return }
            inputText = newValue
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(PlanDateFormatter.friendlyDate(.now))
                .font(.caption.weight(.bold))
                .foregroundStyle(PlanStyle.textSecondary)
            Text("今天想安排什么？")
                .font(.system(size: 31, weight: .heavy))
        }
    }

    private var voiceFocus: some View {
        VStack(spacing: 18) {
            MicStage(isRecording: speechTranscriber.isRecording)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            startPressRecording()
                        }
                        .onEnded { _ in
                            stopPressRecording()
                        }
                )
                .accessibilityLabel(speechTranscriber.isRecording ? "松开停止录音" : "按住开始录音")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    if speechTranscriber.isRecording {
                        stopPressRecording()
                    } else {
                        startPressRecording()
                    }
                }

            VStack(spacing: 7) {
                Text(voiceTitle)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(voiceStatusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(voiceStatusColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: 280)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .planGlassCard(cornerRadius: 28, tint: voiceCardTint)
    }

    private var inputComposer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text("明早 8 点叫我起床")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PlanStyle.textMuted)
                        .padding(.top, 14)
                        .padding(.leading, 14)
                        .allowsHitTesting(false)
                }

                TextField("", text: $inputText, axis: .vertical)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1...5)
                    .fixedSize(horizontal: false, vertical: true)
                    .submitLabel(.send)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .onSubmit {
                        parseInput()
                    }
                    .accessibilityLabel("文本录入")
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            .background(PlanStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(PlanStyle.border, lineWidth: 1)
            }

            Button {
                parseInput()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(sendButtonFill, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.56)
            .accessibilityLabel("解析并确认")
        }
    }

    private var voiceTitle: String {
        speechTranscriber.isRecording ? "正在聆听" : "按住说出安排"
    }

    private var voiceStatusText: String {
        if let error = speechTranscriber.lastErrorMessage {
            return error
        }
        return speechTranscriber.isRecording ? "松开后停止录音" : "按住麦克风开始语音录入"
    }

    private var voiceStatusColor: Color {
        if speechTranscriber.lastErrorMessage != nil {
            return PlanStyle.alarmOrange
        }
        return speechTranscriber.isRecording ? PlanStyle.alertRed : PlanStyle.textSecondary
    }

    private var voiceCardTint: Color {
        speechTranscriber.isRecording ? PlanStyle.alertRed : PlanStyle.calendarBlue
    }

    private var sendButtonFill: Color {
        canSend ? PlanStyle.calendarBlue : PlanStyle.surfaceStrong
    }

    private func startPressRecording() {
        guard !isPressingMic else { return }
        isPressingMic = true
        ignoreTranscriptUpdates = false

        if !speechTranscriber.isRecording {
            speechTranscriber.toggleRecording()
        }
    }

    private func stopPressRecording() {
        guard isPressingMic || speechTranscriber.isRecording else { return }
        isPressingMic = false

        if speechTranscriber.isRecording {
            speechTranscriber.stopRecording()
        }
    }

    private func parseInput() {
        let text = inputText.trimmedPlanText
        guard !text.isEmpty else { return }

        ignoreTranscriptUpdates = true
        isPressingMic = false
        if speechTranscriber.isRecording {
            speechTranscriber.stopRecording()
        }
        onParseRequest(text)
        inputText = ""
    }
}

private struct MicStage: View {
    var isRecording: Bool
    @State private var pulse = false

    private var tint: Color {
        isRecording ? PlanStyle.alertRed : PlanStyle.calendarBlue
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(isRecording ? 0.34 : 0.16), lineWidth: 1)
                .frame(width: 188, height: 188)
                .scaleEffect(isRecording && pulse ? 1.08 : 1)
                .opacity(isRecording && pulse ? 0.42 : 1)

            Circle()
                .fill(tint.opacity(isRecording ? 0.13 : 0.09))
                .frame(width: 148, height: 148)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 108, height: 108)
                .shadow(color: tint.opacity(isRecording ? 0.48 : 0.28), radius: 24, y: 12)

            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 204, height: 204)
        .contentShape(Circle())
        .animation(
            isRecording ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .smooth(duration: 0.2),
            value: pulse
        )
        .task(id: isRecording) {
            pulse = false
            guard isRecording else { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
            pulse = true
        }
    }
}
