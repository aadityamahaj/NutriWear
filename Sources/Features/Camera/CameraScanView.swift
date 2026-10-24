import SwiftUI
import AVFoundation

/// Full-screen camera (or photo fallback) with a scanning overlay and a big
/// circular capture button. On capture, hands the frame to AppModel for AI
/// recognition and presents the analysis bottom sheet.
struct CameraScanView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraService()

    @State private var showPhotoPicker = false
    @State private var capturedImage: UIImage?
    @State private var showAnalysis = false
    @State private var scanPhase: CGFloat = 0
    @State private var mealType = AppModel.suggestedMealType()

    private let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Live preview or fallback backdrop
            if !CameraService.isSimulator && camera.authState == .authorized {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else {
                fallbackBackdrop
            }

            scanningOverlay

            VStack {
                topBar
                Spacer()
                bottomControls
            }
            .padding()

            if model.isRecognizing {
                recognizingOverlay
            }
        }
        .task {
            if !CameraService.isSimulator {
                await camera.requestAccess()
                camera.start()
            }
        }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker { image in
                capturedImage = image
                Task { await analyze(image) }
            }
        }
        .sheet(isPresented: $showAnalysis) {
            // Keep the camera open after a meal is logged/discarded so the user
            // can scan the next one. They leave via the ✕ button.
            AnalysisSheet(capturedImage: capturedImage, onScanMore: {
                showAnalysis = false
            })
                .environmentObject(model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Pieces

    private var fallbackBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.08), Color(white: 0.02)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                Text(CameraService.isSimulator ? "Simulator has no camera" : "Camera unavailable")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Pick a meal photo to analyze")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .ignoresSafeArea()
    }

    private var scanningOverlay: some View {
        GeometryReader { geo in
            let box = min(geo.size.width, geo.size.height) * 0.72
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 2)
                    .frame(width: box, height: box)
                    .overlay(scanLine(box: box))
                    .overlay(corners(box: box))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }

    private func scanLine(box: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Theme.calories.opacity(0.9), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(height: 3)
            .offset(y: -box / 2 + scanPhase * box)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                    scanPhase = 1
                }
            }
            .mask(RoundedRectangle(cornerRadius: 28).frame(width: box, height: box))
    }

    private func corners(box: CGFloat) -> some View {
        // Decorative corner accents
        let corner = 26.0
        return ZStack {
            ForEach(0..<4) { i in
                CornerShape()
                    .stroke(Theme.calories, lineWidth: 3)
                    .frame(width: corner, height: corner)
                    .rotationEffect(.degrees(Double(i) * 90))
                    .position(cornerPosition(i, box: box))
            }
        }
        .frame(width: box, height: box)
    }

    private func cornerPosition(_ i: Int, box: CGFloat) -> CGPoint {
        let inset = 2.0
        switch i {
        case 0: return CGPoint(x: inset + 13, y: inset + 13)
        case 1: return CGPoint(x: box - inset - 13, y: inset + 13)
        case 2: return CGPoint(x: box - inset - 13, y: box - inset - 13)
        default: return CGPoint(x: inset + 13, y: box - inset - 13)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black.opacity(0.4)))
            }
            Spacer()
            // Meal type picker
            Menu {
                ForEach(mealTypes, id: \.self) { type in
                    Button(type) { mealType = type }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(mealType).font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(.black.opacity(0.4)))
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 16) {
            Text(CameraService.isSimulator
                 ? "Tap the photo icon to choose a meal"
                 : "Center your plate, then tap to scan")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(.black.opacity(0.4)))

            HStack {
                // Photo library button
                Button {
                    showPhotoPicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(.black.opacity(0.4)))
                }
                Spacer()

                // Big capture button
                Button {
                    Task { await captureAndAnalyze() }
                } label: {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 82, height: 82)
                        Circle().fill(.white).frame(width: 68, height: 68)
                    }
                }
                .disabled(CameraService.isSimulator)
                .opacity(CameraService.isSimulator ? 0.4 : 1)

                Spacer()
                // Spacer to balance layout
                Color.clear.frame(width: 52, height: 52)
            }
        }
        .padding(.bottom, 10)
    }

    private var recognizingOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().tint(Theme.calories).scaleEffect(1.4)
                Text("Analyzing your plate…")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(model.aiConfigured ? "Groq vision is identifying foods" : "Using offline sample")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Actions

    private func captureAndAnalyze() async {
        guard let image = await camera.capturePhoto() else { return }
        capturedImage = image
        await analyze(image)
    }

    private func analyze(_ image: UIImage) async {
        // If a meal is already pending (user tapped "Scan another item"), merge
        // the new foods into it; otherwise start a fresh meal.
        if model.pendingMeal != nil {
            await model.recognizeMore(image: image, mealType: mealType)
        } else {
            await model.recognize(image: image, mealType: mealType)
        }
        if model.pendingMeal != nil {
            showAnalysis = true
        }
    }
}

/// An L-shaped corner accent.
struct CornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}
