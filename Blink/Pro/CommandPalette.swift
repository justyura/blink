//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K   P R O
//
// A Spotlight-style palette shown over the terminal: a text field plus an
// optional list of items. Used by the session jumper and the web search bar.
//
//////////////////////////////////////////////////////////////////////////////////

import SwiftUI
import UIKit

struct PaletteItem: Identifiable, Equatable {
  let id: String
  var badge: String
  var title: String
  var subtitle: String
  var isCurrent: Bool = false
}

final class PaletteModel: ObservableObject {
  let title: String
  let placeholder: String
  let footer: String
  let items: [PaletteItem]

  /// Hide the text field for plain menus (touch use).
  var showsSearchField = true

  @Published var query: String = ""
  @Published var selectedIndex: Int = 0

  /// Called with the query and the highlighted item (nil when there are no items).
  var onSubmit: (String, PaletteItem?) -> Void = { _, _ in }
  var onCancel: () -> Void = {}

  init(title: String, placeholder: String, footer: String = "", items: [PaletteItem] = []) {
    self.title = title
    self.placeholder = placeholder
    self.footer = footer
    self.items = items
    self.selectedIndex = items.firstIndex(where: { $0.isCurrent }) ?? 0
  }

  var filteredItems: [PaletteItem] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return items }
    // A bare number selects that session directly.
    if let n = Int(q), n >= 1, n <= items.count {
      return [items[n - 1]]
    }
    return items.filter {
      $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) || $0.badge == q
    }
  }

  func move(_ delta: Int) {
    let count = filteredItems.count
    guard count > 0 else { return }
    selectedIndex = (selectedIndex + delta + count) % count
  }

  func submit() {
    let list = filteredItems
    let item = list.isEmpty ? nil : list[min(selectedIndex, list.count - 1)]
    onSubmit(query, item)
  }
}

struct PaletteView: View {
  @ObservedObject var model: PaletteModel
  @FocusState private var focused: Bool

  var body: some View {
    ZStack(alignment: .top) {
      Color.black.opacity(0.35)
        .ignoresSafeArea()
        .onTapGesture { model.onCancel() }

      VStack(spacing: 0) {
        if !model.showsSearchField {
          HStack {
            Text(model.title).font(.headline)
            Spacer()
            Button(action: { model.onCancel() }) {
              Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.title3)
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
        } else {
        HStack(spacing: 10) {
          Image(systemName: model.items.isEmpty ? "magnifyingglass" : "rectangle.stack")
            .foregroundColor(.secondary)
          TextField(model.placeholder, text: $model.query)
            .textFieldStyle(.plain)
            .font(.system(size: 20, weight: .regular, design: .rounded))
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .keyboardType(model.items.isEmpty ? .webSearch : .default)
            .submitLabel(.go)
            .focused($focused)
            .onSubmit { model.submit() }
            .onChange(of: model.query) { _ in model.selectedIndex = 0 }
          Text(model.title)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        }

        let list = model.filteredItems
        if !list.isEmpty {
          Divider()
          ScrollViewReader { proxy in
            ScrollView {
              LazyVStack(spacing: 2) {
                ForEach(Array(list.enumerated()), id: \.element.id) { idx, item in
                  PaletteRow(item: item, selected: idx == model.selectedIndex)
                    .id(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                      model.selectedIndex = idx
                      model.submit()
                    }
                }
              }
              .padding(8)
            }
            .frame(maxHeight: 360)
            .onChange(of: model.selectedIndex) { idx in
              if idx < list.count { proxy.scrollTo(list[idx].id) }
            }
          }
        } else if !model.items.isEmpty {
          Divider()
          Text("No matching session")
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(14)
        }

        if !model.footer.isEmpty {
          Divider()
          Text(model.footer)
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
      }
      .background(.regularMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.12)))
      .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
      .frame(maxWidth: 640)
      .padding(.horizontal, 24)
      .padding(.top, 72)
    }
    .onAppear {
      if model.showsSearchField {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
      }
    }
  }
}

private struct PaletteRow: View {
  let item: PaletteItem
  let selected: Bool

  var body: some View {
    HStack(spacing: 12) {
      Text(item.badge)
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .frame(width: 28, height: 28)
        .background(Circle().fill(selected ? Color.accentColor : Color.secondary.opacity(0.2)))
        .foregroundColor(selected ? .white : .primary)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.system(size: 16, weight: .medium))
          .lineLimit(1)
        if !item.subtitle.isEmpty {
          Text(item.subtitle)
            .font(.footnote)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
      }
      Spacer()
      if item.isCurrent {
        Image(systemName: "checkmark").foregroundColor(.secondary).font(.footnote)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
    )
  }
}

/// Hosts the palette and routes hardware keys (Esc, arrows, Ctrl-N/P) to the model.
final class PaletteViewController: UIHostingController<PaletteView> {
  let model: PaletteModel

  init(model: PaletteModel) {
    self.model = model
    super.init(rootView: PaletteView(model: model))
    view.backgroundColor = .clear
  }

  @MainActor required dynamic init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var canBecomeFirstResponder: Bool { true }

  override var keyCommands: [UIKeyCommand]? {
    let cmds = [
      UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(paletteCancel)),
      UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(paletteUp)),
      UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(paletteDown)),
      UIKeyCommand(input: "p", modifierFlags: .control, action: #selector(paletteUp)),
      UIKeyCommand(input: "n", modifierFlags: .control, action: #selector(paletteDown)),
      UIKeyCommand(input: "[", modifierFlags: .control, action: #selector(paletteCancel)),
    ]
    cmds.forEach { $0.wantsPriorityOverSystemBehavior = true }
    return cmds
  }

  @objc private func paletteCancel() { model.onCancel() }
  @objc private func paletteUp() { model.move(-1) }
  @objc private func paletteDown() { model.move(1) }
}
