import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// Private Fortschrittsfotos. Sie verbleiben lokal und werden nie automatisch geteilt.
struct ProgressPhotosView: View {
    @Environment(AppPreferences.self) private var prefs

    var body: some View {
        ProgressSensitiveGate(isRequired: prefs.lockSensitiveModules,
                              reason: "Entsperre deine Fortschrittsfotos.") {
            ProgressPhotosContent()
        }
        .navigationTitle("Fortschrittsfotos")
    }
}

private struct ProgressPhotosContent: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]

    @State private var poseFilter: PhotoPose? = nil
    @State private var pickerItem: PhotosPickerItem?
    @State private var newPose: PhotoPose = .front
    @State private var isShowingCamera = false
    @State private var isSelecting = false
    @State private var selection: [UUID] = []
    @State private var isComparing = false
    @State private var detailPhoto: ProgressPhoto?
    @State private var pendingDelete: ProgressPhoto?

    private var filtered: [ProgressPhoto] {
        guard let poseFilter else { return photos }
        return photos.filter { $0.pose == poseFilter }
    }

    private var grouped: [(key: String, date: Date, items: [ProgressPhoto])] {
        let groups = Dictionary(grouping: filtered) { DayKey.make($0.date) }
        return groups.map { (key: $0.key, date: $0.value.first?.date ?? .now, items: $0.value) }
            .sorted { $0.date > $1.date }
    }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                InfoNote(text: "Deine Fotos werden nur auf diesem Gerät gespeichert und nie ohne deine ausdrückliche Aktion geteilt.",
                         symbol: "lock")

                Picker("Pose", selection: $poseFilter) {
                    Text("Alle").tag(PhotoPose?.none)
                    ForEach(PhotoPose.allCases) { Text($0.title).tag(PhotoPose?.some($0)) }
                }
                .pickerStyle(.segmented)

                if photos.isEmpty {
                    ContentUnavailableView("Noch keine Fotos", systemImage: "photo.on.rectangle",
                                           description: Text("Fotos aus gleicher Perspektive und bei gleichem Licht machen Veränderungen am besten sichtbar."))
                        .padding(.top, Theme.Space.xl)
                }

                ForEach(grouped, id: \.key) { group in
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Text(Fmt.mediumDate(group.date))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(group.items) { photo in
                                tile(photo)
                            }
                        }
                    }
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                HStack {
                    Text(selection.count == 2 ? "Bereit zum Vergleich" : "Wähle zwei Fotos (\(selection.count)/2)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Vergleichen") { isComparing = true }
                        .buttonStyle(.glassProminent)
                        .disabled(selection.count != 2)
                }
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, Theme.Space.m)
                .padding(.bottom, Theme.Space.xs)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Fertig" : "Vergleichen") {
                    isSelecting.toggle()
                    selection = []
                }
                .disabled(photos.count < 2 && !isSelecting)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Pose", selection: $newPose) {
                        ForEach(PhotoPose.allCases) { Text($0.title).tag($0) }
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { isShowingCamera = true } label: { Label("Foto aufnehmen", systemImage: "camera") }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Aus Mediathek", systemImage: "photo")
                    }
                } label: {
                    Label("Foto hinzufügen", systemImage: "plus")
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    save(data)
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            ProgressCameraPicker(isPresented: $isShowingCamera) { image in
                if let data = image.jpegData(compressionQuality: 0.9) { save(data) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isComparing) {
            compareSheet
        }
        .sheet(item: $detailPhoto, onDismiss: performPendingDelete) { photo in
            ProgressPhotoDetail(photo: photo) {
                pendingDelete = photo
                detailPhoto = nil
            }
        }
    }

    private func performPendingDelete() {
        guard let photo = pendingDelete else { return }
        pendingDelete = nil
        selection.removeAll { $0 == photo.id }
        context.delete(photo)
        context.saveQuietly()
    }

    @ViewBuilder
    private func tile(_ photo: ProgressPhoto) -> some View {
        let selected = selection.contains(photo.id)
        Button {
            if isSelecting {
                if let index = selection.firstIndex(of: photo.id) {
                    selection.remove(at: index)
                } else if selection.count < 2 {
                    selection.append(photo.id)
                }
            } else {
                detailPhoto = photo
            }
        } label: {
            Color.clear
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay { ProgressPhotoImage(data: photo.imageData) }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .overlay(alignment: .topLeading) {
                    Badge(text: photo.pose.title, tint: .white)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(selected ? Theme.accent : .white)
                            .padding(6)
                    }
                }
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .stroke(Theme.accent, lineWidth: 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Foto \(photo.pose.title), \(Fmt.mediumDate(photo.date))")
    }

    private var compareSheet: some View {
        let chosen = selection.compactMap { id in photos.first { $0.id == id } }.sorted { $0.date < $1.date }
        return NavigationStack {
            HStack(spacing: 8) {
                ForEach(chosen) { photo in
                    VStack(spacing: 6) {
                        ProgressPhotoImage(data: photo.imageData, fit: true)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                        Text(Fmt.mediumDate(photo.date)).font(.caption.weight(.semibold))
                        Text(photo.pose.title).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.screenPadding)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .navigationTitle(compareTitle(chosen))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { isComparing = false }
                }
            }
        }
    }

    private func compareTitle(_ chosen: [ProgressPhoto]) -> String {
        guard chosen.count == 2 else { return "Vergleich" }
        let days = Int(chosen[1].date.timeIntervalSince(chosen[0].date) / 86_400)
        return days == 1 ? "1 Tag Unterschied" : "\(days) Tage Unterschied"
    }

    private func save(_ data: Data) {
        let resized = ProgressImageTools.downscaled(data, maxDimension: 2000) ?? data
        let photo = ProgressPhoto(imageData: resized, pose: newPose)
        context.insert(photo)
        context.saveQuietly()
    }
}

private struct ProgressPhotoDetail: View {
    @Bindable var photo: ProgressPhoto
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProgressPhotoImage(data: photo.imageData, fit: true)
                        .frame(maxHeight: 420)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    Picker("Pose", selection: Binding(get: { photo.pose }, set: { photo.poseRaw = $0.rawValue })) {
                        ForEach(PhotoPose.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Datum", selection: $photo.date, in: ...Date.now, displayedComponents: .date)
                    TextField("Private Notiz", text: $photo.note, axis: .vertical)
                }
                Section {
                    Button("Foto löschen", role: .destructive) { isConfirmingDelete = true }
                }
            }
            .confirmationDialog("Foto löschen?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive, action: onDelete)
            } message: {
                Text("Das Foto wird endgültig von diesem Gerät entfernt.")
            }
            .navigationTitle(Fmt.mediumDate(photo.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

/// Zeigt Bilddaten effizient an (Thumbnail-Dekodierung im Hintergrund).
private struct ProgressPhotoImage: View {
    let data: Data
    var fit: Bool = false
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.fill
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
            }
        }
        .clipped()
        .task(id: data.count) {
            let source = data
            let maxDim: CGFloat = fit ? 1600 : 500
            image = await Task.detached(priority: .userInitiated) {
                ProgressImageTools.thumbnail(source, maxDimension: maxDim)
            }.value
        }
    }
}

enum ProgressImageTools {
    static func thumbnail(_ data: Data, maxDimension: CGFloat) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        return image.preparingThumbnail(of: fittedSize(image.size, max: maxDimension)) ?? image
    }

    static func downscaled(_ data: Data, maxDimension: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = fittedSize(image.size, max: maxDimension)
        let renderer = UIGraphicsImageRenderer(size: size)
        let scaled = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return scaled.jpegData(compressionQuality: 0.85)
    }

    private static func fittedSize(_ size: CGSize, max: CGFloat) -> CGSize {
        let longest = Swift.max(size.width, size.height)
        guard longest > max, longest > 0 else { return size }
        let factor = max / longest
        return CGSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())
    }
}

/// Kamera-Aufnahme über UIImagePickerController.
struct ProgressCameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProgressCameraPicker
        init(_ parent: ProgressCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
