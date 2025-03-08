import SwiftUI
import ApplicationServices

struct PopupView: View {
    @ObservedObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("use_gradient_theme") private var useGradientTheme = false
    @State private var customText: String = ""
    @State private var isCustomLoading: Bool = false
    @State private var processingCommandId: UUID? = nil
    
    // Make edit mode publicly accessible with property wrapper
    // This allows the window to observe changes to edit mode
    @State public var isEditMode = false
    
    @State private var showingCommandsView = false
    @State private var editingCommand: CommandModel? = nil
    let closeAction: () -> Void
    
    // Grid layout for two columns
    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            // Top bar with buttons
            HStack {
                Button(action: {
                    if isEditMode {
                        isEditMode = false
                    } else {
                        closeAction()
                    }
                }) {
                    Image(systemName: isEditMode ? "xmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.leading, 8)
                
                Spacer()
                
                Button(action: {
                    // Toggle edit mode and notify parent window to adjust size
                    isEditMode.toggle()
                    
                    // Use a notification to trigger window size update
                    NotificationCenter.default.post(name: NSNotification.Name("EditModeChanged"), object: nil)
                }) {
                    Image(systemName: isEditMode ? "checkmark.circle.fill" : "square.and.pencil.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 8)
            }
            
            // Custom input with send button
            if !isEditMode {
                HStack(spacing: 8) {
                    TextField(
                        appState.selectedText.isEmpty ? "Describe your change..." : "Describe your change...",
                        text: $customText
                    )
                    .textFieldStyle(.plain)
                    .appleStyleTextField(
                        text: customText,
                        isLoading: isCustomLoading,
                        onSubmit: processCustomChange
                    )
                }
                .padding(.horizontal)
            }
            
            if !appState.selectedText.isEmpty || !appState.selectedImages.isEmpty {
                // Command buttons grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(appState.commandManager.commands) { command in
                            CommandButton(
                                command: command,
                                isEditing: isEditMode,
                                isLoading: processingCommandId == command.id,
                                onTap: {
                                    processingCommandId = command.id
                                    appState.processCommand(command)
                                    
                                    // Reset loading state after a short delay
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        processingCommandId = nil
                                    }
                                },
                                onEdit: {
                                    editingCommand = command
                                    showingCommandsView = true
                                },
                                onDelete: {
                                    print("Deleting command: \(command.name)")
                                    appState.commandManager.deleteCommand(command)
                                    
                                    // Notify that a command was deleted to adjust window size
                                    NotificationCenter.default.post(name: NSNotification.Name("CommandsChanged"), object: nil)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 8)
            }
            
            if isEditMode {
                Button(action: { showingCommandsView = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Manage Commands")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 8)
        .windowBackground(useGradient: useGradientTheme)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
        .sheet(isPresented: $showingCommandsView) {
            CommandsView(commandManager: appState.commandManager)
                .onDisappear {
                    // Trigger window resize when returning from CommandsView
                    // as commands may have been added/removed
                    NotificationCenter.default.post(name: NSNotification.Name("CommandsChanged"), object: nil)
                }
        }
    }
    
    private func processCommand(_ command: CommandModel) {
        guard !appState.selectedText.isEmpty else { return }
        
        appState.processCommand(command)
    }
    
    // Process custom text input
    private func processCustomChange() {
        guard !customText.isEmpty && !appState.selectedText.isEmpty else { return }
        
        isCustomLoading = true
        
        let systemPrompt = """
        You are a helpful AI assistant. Your task is to modify the text according to the following instructions:
        
        \(customText)
        
        Only return the modified text. Do not provide explanations or extra text unless specifically asked for in the instructions.
        """
        
        Task {
            do {
                let result = try await appState.activeProvider.processText(
                    systemPrompt: systemPrompt,
                    userPrompt: appState.selectedText,
                    images: []
                )
                
                DispatchQueue.main.async {
                    appState.replaceSelectedText(with: result)
                    customText = ""
                    isCustomLoading = false
                    closeAction()
                }
            } catch {
                print("Error processing custom prompt: \(error)")
                isCustomLoading = false
            }
        }
    }
}

struct OptionButton: View {
    let option: WritingOption
    let action: () -> Void
    let isLoading: Bool
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: option.icon)
                Text(option.localizedName)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 140)
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(LoadingButtonStyle(isLoading: isLoading))
        .disabled(isLoading)
    }
}


struct CustomOptionButton: View {
    let command: CustomCommand
    let action: () -> Void
    let isLoading: Bool
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: command.icon)
                Text(command.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 140)
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(LoadingButtonStyle(isLoading: isLoading))
        .disabled(isLoading)
    }
}
