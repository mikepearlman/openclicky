import Foundation

@main
struct ExternalModelCatalogChecks {
    static func main() {
        let chatGPT = OpenClickyModelCatalog.voiceResponseModel(withID: "gpt-5.6-luna")
        let openCode = OpenClickyModelCatalog.voiceResponseModel(withID: "opencode-go/gpt-5.6-luna")
        precondition(chatGPT.provider == .openAI)
        precondition(openCode.provider == .openCodeGo)
        precondition(chatGPT.id != openCode.id)
        precondition(openCode.remoteModelID == "gpt-5.6-luna")

        let nvidiaID = "nvidia/nvidia/nemotron-3.5-lightning-30b-a3b"
        let nvidia = OpenClickyModelCatalog.voiceResponseModel(withID: nvidiaID)
        precondition(nvidia.provider == .nvidia)
        precondition(nvidia.remoteModelID == "nvidia/nemotron-3.5-lightning-30b-a3b")
        precondition(OpenClickyModelCatalog.voiceAnalysisModel(withID: nvidiaID).id == nvidiaID)
        precondition(!OpenClickyModelCatalog.isSpeechModelID(nvidiaID))
        precondition(OpenClickyModelCatalog.externalModelOption(withID: "opencode-go/") == nil)

        // Outside models must never leak into the ChatGPT-only task runner.
        precondition(OpenClickyModelCatalog.codexActionsModel(withID: nvidiaID).id == "gpt-5.6-sol")
        precondition(OpenClickyModelCatalog.computerUseModel(withID: nvidiaID).provider == .codex)
        print("PASS: provider separation, model IDs, screen analysis, and task routing")
    }
}
