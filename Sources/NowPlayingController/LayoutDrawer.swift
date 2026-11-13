import SwiftUI

/// Slide-out panel for editing the layout in place: drag widgets from here onto the deck,
/// and move, resize, configure or remove them directly on the deck while it's open.
struct LayoutDrawer: View {
    @AppStorage("canvasColumnCount") private var columnCount = 4
    @AppStorage("headerLayoutStyle") private var headerLayoutStyle = "standard"
    @AppStorage("footerLayoutStyle") private var footerLayoutStyle = "standard"
    @State private var search = ""
    @State private var collapsed: Set<String> = []
    @State private var showsPresets = false
    private var session: LayoutEditSession { .shared }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    layoutControls
                    PresetsSection(expanded: $showsPresets)
                    Divider()
                    gallery
                }
                .padding(12)
            }
            Divider()
            Text("Drag a preview onto the deck, or click it to add. On the deck: drag to move, ⚙︎ for settings, the corner handle to resize, × to remove.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(12)
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1) }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Edit Layout").font(.headline)
                Text("Changes apply as you make them").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { session.end() }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.top, 38) // clear the window's traffic-light buttons
        .padding(.bottom, 10)
    }

    private var layoutControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper("Columns: \(columnCount)", value: $columnCount, in: 1...8)
                .onChange(of: columnCount) { _, _ in WidgetLayoutStore.save(WidgetLayoutStore.load()) }
            BannerPicker(zone: "header", title: "Header", height: $headerLayoutStyle)
            BannerPicker(zone: "footer", title: "Footer", height: $footerLayoutStyle)
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Widgets").font(.subheadline.bold())
            TextField("Search widgets", text: $search).textFieldStyle(.roundedBorder)
            LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
                ForEach(WidgetGroups.all, id: \.name) { group in
                    let kinds = group.kinds.filter(matches)
                    if !kinds.isEmpty {
                        Section {
                            if !collapsed.contains(group.name) || !search.isEmpty {
                                ForEach(kinds, id: \.self) { DrawerWidgetRow(kind: $0) }
                            }
                        } header: {
                            groupHeader(group.name, icon: group.icon, count: kinds.count)
                        }
                    }
                }
            }
        }
    }

    private func matches(_ kind: String) -> Bool {
        search.isEmpty || WidgetLayoutStore.name(kind).localizedCaseInsensitiveContains(search) || kind.localizedCaseInsensitiveContains(search)
    }

    private func groupHeader(_ name: String, icon: String, count: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsed.contains(name) { collapsed.remove(name) } else { collapsed.insert(name) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).frame(width: 18)
                Text(name).font(.subheadline.bold())
                Text("\(count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(collapsed.contains(name) && search.isEmpty ? -90 : 0))
            }
            .padding(.horizontal, 6).padding(.vertical, 7)
            .background(.regularMaterial)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared helpers

@MainActor
private enum DrawerLayout {
    static var columns: Int {
        max(1, UserDefaults.standard.object(forKey: "canvasColumnCount") == nil ? 4 : UserDefaults.standard.integer(forKey: "canvasColumnCount"))
    }

    static func add(_ kind: String, size: String) {
        let before = WidgetLayoutStore.load()
        var editing = LayoutEditing(before, columns: columns)
        editing.drop("new:\(kind):\(size)", zone: "body")
        LayoutEditSession.shared.noteAdded(before: before, after: editing.instances)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { WidgetLayoutStore.save(editing.instances) }
    }

    /// Puts `kind` in the header or footer, replacing what's there (nil empties the slot).
    static func setBanner(_ kind: String?, zone: String) {
        var editing = LayoutEditing(WidgetLayoutStore.load().filter { $0.zone != zone }, columns: columns)
        if let kind { editing.drop("new:\(kind):medium", zone: zone) }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { WidgetLayoutStore.save(editing.instances) }
    }

    static func dragProvider(_ payload: String) -> NSItemProvider {
        LayoutEditSession.shared.payload = payload
        return NSItemProvider(object: payload as NSString)
    }
}

// MARK: - Widget rows

/// One widget: a live preview for each grid size. Previews can be dragged onto the deck or
/// clicked to add the widget in the first free space.
private struct DrawerWidgetRow: View {
    let kind: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(WidgetLayoutStore.name(kind), systemImage: WidgetLayoutStore.icon(kind))
                .font(.system(size: 13, weight: .semibold)).lineLimit(1)
            HStack(alignment: .top, spacing: 8) {
                preview("small", label: "1×1", width: 64, height: 64)
                preview("medium", label: "2×1", width: 134, height: 64)
                if kind != "audio" { preview("large", label: "2×2", width: 64, height: 64) }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func preview(_ size: String, label: String, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 3) {
            LiveWidgetPreview(kind: kind, size: size)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.8))
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .clickAction { DrawerLayout.add(kind, size: size) }
        .onDrag { DrawerLayout.dragProvider("new:\(kind):\(size)") }
        .help("\(WidgetLayoutStore.name(kind)) \(label): drag onto the deck or click to add")
    }
}

// MARK: - Header / footer picker

/// Dropdown for the header or footer, showing the current banner and a previewed list.
private struct BannerPicker: View {
    let zone: String
    let title: String
    @Binding var height: String
    @State private var open = false
    @State private var search = ""
    @State private var current: WidgetInstance?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                Picker("", selection: $height) {
                    Text("Slim").tag("slim")
                    Text("Standard").tag("standard")
                    Text("Tall").tag("tall")
                }
                .labelsHidden().controlSize(.small).fixedSize()
            }
            Button { open = true } label: {
                HStack(spacing: 8) {
                    if let current {
                        LiveWidgetPreview(kind: current.kind, size: "banner")
                            .aspectRatio(880.0 / 140.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Text("None").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 36)
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
                }
                .padding(5)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(current.map { "\(title): \(WidgetLayoutStore.name($0.kind))" } ?? "Choose a \(title.lowercased()) banner")
            .popover(isPresented: $open, arrowEdge: .leading) { list }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .splitDeckWidgetLayoutChanged)) { _ in reload() }
    }

    private func reload() { current = WidgetLayoutStore.load().first { $0.zone == zone } }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title) Banner").font(.headline)
            TextField("Search", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    option(nil)
                    ForEach(WidgetGroups.all, id: \.name) { group in
                        let kinds = group.kinds.filter { search.isEmpty || WidgetLayoutStore.name($0).localizedCaseInsensitiveContains(search) }
                        if !kinds.isEmpty {
                            Text(group.name).font(.caption.bold()).foregroundStyle(.secondary).textCase(.uppercase).padding(.top, 4)
                            ForEach(kinds, id: \.self) { option($0) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .frame(width: 360, height: 520)
    }

    private func option(_ kind: String?) -> some View {
        let selected = current?.kind == kind
        return Button {
            DrawerLayout.setBanner(kind, zone: zone)
            open = false
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(kind.map(WidgetLayoutStore.name) ?? "None").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                }
                if let kind {
                    LiveWidgetPreview(kind: kind, size: "banner")
                        .aspectRatio(880.0 / 140.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(6)
            .background(selected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Presets

private struct PresetsSection: View {
    @Binding var expanded: Bool
    @State private var saved = NamedLayoutPreset.load()
    @State private var newName = ""
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var confirmsReset = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Built-in presets fit the current column count.").font(.caption).foregroundStyle(.secondary)
                FlowRow(spacing: 6) {
                    ForEach(SplitDeckPresetManager.builtIn, id: \.id) { preset in
                        Button(preset.name) { SplitDeckPresetManager.applyBuiltIn(preset.id) }
                            .buttonStyle(FocusChipStyle(selected: false, accent: .accentColor))
                    }
                }
                if !saved.isEmpty {
                    Text("Your presets").font(.caption.bold()).foregroundStyle(.secondary).textCase(.uppercase)
                    ForEach(saved) { preset in savedRow(preset) }
                }
                HStack {
                    TextField("Name", text: $newName).textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save Current", action: save)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Reset to Default Layout…", role: .destructive) { confirmsReset = true }
                    .buttonStyle(.borderless).font(.caption)
            }
            .padding(.top, 6)
        } label: {
            Text("Presets").font(.subheadline.bold())
        }
        .confirmationDialog("Reset widget layout?", isPresented: $confirmsReset) {
            Button("Reset to Default Layout", role: .destructive) {
                UserDefaults.standard.set(4, forKey: "canvasColumnCount")
                WidgetLayoutStore.save(WidgetLayoutStore.defaults)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This restores the default widget positions, sizes, header and footer. Saved presets are kept.")
        }
    }

    private func savedRow(_ preset: NamedLayoutPreset) -> some View {
        HStack(spacing: 6) {
            if renaming == preset.id {
                TextField("Name", text: $renameText).textFieldStyle(.roundedBorder)
                    .onSubmit { SplitDeckPresetManager.rename(preset.id, to: renameText); renaming = nil; reload() }
                Button("OK") { SplitDeckPresetManager.rename(preset.id, to: renameText); renaming = nil; reload() }
            } else {
                Button { SplitDeckPresetManager.apply(preset) } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
                        Text(preset.name).lineLimit(1)
                        Spacer()
                        Text("\(preset.columns) col").font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Apply \(preset.name)")
                Menu {
                    Button("Apply") { SplitDeckPresetManager.apply(preset) }
                    Button("Update to Current Layout") { SplitDeckPresetManager.update(preset.id); reload() }
                    Button("Rename…") { renameText = preset.name; renaming = preset.id }
                    Divider()
                    Button("Delete", role: .destructive) { SplitDeckPresetManager.delete(preset.id); reload() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
        .padding(6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func save() {
        SplitDeckPresetManager.saveCurrent(as: newName)
        newName = ""
        reload()
    }

    private func reload() { saved = NamedLayoutPreset.load() }
}

/// Wraps chips onto multiple lines.
private struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(width, maxX), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
