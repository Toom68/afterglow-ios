import SwiftUI

struct SettingsView: View {
    var lightStatus: String
    var onEraseHistory: () -> Void
    @State private var confirmingErase = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: "A little context")
                        Text("Made for a quieter moment.")
                            .agFont(34, weight: .regular, design: .serif)
                        Text("Afterglow is an independent meditation prototype, inspired by the session-and-reflection approach of Lumenate.")
                            .agFont(15).foregroundStyle(AfterglowTheme.muted)
                            .lineSpacing(5)
                    }

                    AfterglowCard {
                        VStack(alignment: .leading, spacing: 15) {
                            Label("The method", systemImage: "sparkle")
                                .agFont(17, weight: .medium)
                            Text("Lumenate combines sound with flashing light viewed through closed eyelids. Flicker can produce colours, patterns, and changes in subjective experience. The exact experience varies between people.")
                                .foregroundStyle(AfterglowTheme.muted)
                            Text("That does not establish a treatment for anxiety, sleep problems, or any other condition. Afterglow does not reproduce Lumenate’s undisclosed light sequences or claim the same effects.")
                                .foregroundStyle(AfterglowTheme.muted)
                            Text(lightStatus)
                                .agFont(13, weight: .medium)
                                .foregroundStyle(AfterglowTheme.gold)
                        }
                        .agFont(14).lineSpacing(4)
                    }

                    AfterglowCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Your space stays yours", systemImage: "lock.shield")
                                .agFont(17, weight: .medium)
                            Text("No account, ads, analytics, or AI chat. Sessions work offline. Your intentions and reflections are stored on this device; iOS device backups may include app data.")
                                .agFont(14).foregroundStyle(AfterglowTheme.muted)
                                .lineSpacing(4)
                            Text("Use your device passcode to protect your phone. Deleting the app removes its local data, subject to any backups you keep.")
                                .agFont(13).foregroundStyle(AfterglowTheme.muted)
                        }
                    }

                    AfterglowCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("Keep it comfortable", systemImage: "hand.raised")
                                .agFont(17, weight: .medium)
                            Text("Use audio at a comfortable volume, seated or lying down somewhere quiet. Breathe naturally; there is no need to hold your breath or force a rhythm. Stop if you feel uncomfortable. Do not use while driving or doing anything that needs your attention.")
                                .agFont(14).foregroundStyle(AfterglowTheme.muted)
                                .lineSpacing(4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(title: "Further reading")
                        Link(destination: URL(string: "https://lumenate.co/")!) {
                            HStack {
                                Text("The original Lumenate app")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .agFont(14).foregroundStyle(AfterglowTheme.gold)
                            .padding(18).background(AfterglowTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                        }
                        Text("The source package includes detailed product and science reports, citations, limitations, and installation instructions.")
                            .agFont(12).foregroundStyle(AfterglowTheme.muted).lineSpacing(4)
                    }

                    Button(role: .destructive) { confirmingErase = true } label: {
                        Label("Erase journal and session history", systemImage: "trash")
                            .agFont(14).frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .confirmationDialog("Erase all local reflections and session history?", isPresented: $confirmingErase, titleVisibility: .visible) {
                        Button("Erase my data", role: .destructive, action: onEraseHistory)
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This cannot be undone. Any copies you exported or backed up are separate.")
                    }
                    Text("AFTERGLOW  /  INDEPENDENT PROTOTYPE")
                        .agFont(9, design: .monospaced).tracking(1.6)
                        .foregroundStyle(AfterglowTheme.muted).frame(maxWidth: .infinity)
                }
                .padding(24)
                .padding(.bottom, 24)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .afterglowScreen()
        }
    }
}
