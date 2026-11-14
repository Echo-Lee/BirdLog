// WhisperKit (Argmax OSS) setup: model loading + decoding options.
//
// Mirrors the structure of the hackathon sample's argmax-pro-sdk/native
// Bootstrap.swift. In the Pro SDK the species list goes into
// WhisperKitProConfig(customVocabularyConfig:); in the OSS SDK the equivalent
// is decoder prompt conditioning via DecodingOptions.promptTokens.

import ArgmaxCore
import Foundation
import WhisperKit

enum Bootstrap {
    /// Common local birding vocabulary used to bias decoding. The last
    /// `promptTokenBudget` tokens of the encoded prompt are kept (Whisper
    /// conditions on the tail of the prompt).
    static let birdingPrompt = """
        Birding field notes. Start checklist, end checklist. Species: Mallard, \
        Wood Duck, American Black Duck, Canada Goose, Mute Swan, Green-winged Teal, \
        Northern Shoveler, Gadwall, Bufflehead, Hooded Merganser, Common Merganser, \
        Ring-necked Duck, Common Loon, Pied-billed Grebe, Double-crested Cormorant, \
        Great Blue Heron, Turkey Vulture, Black Vulture, Red-tailed Hawk, \
        Sharp-shinned Hawk, Cooper's Hawk, Red-shouldered Hawk, Bald Eagle, Osprey, \
        American Kestrel, Peregrine Falcon, Belted Kingfisher, Red-bellied Woodpecker, \
        Downy Woodpecker, Hairy Woodpecker, Pileated Woodpecker, Northern Flicker, \
        Blue Jay, American Crow, Common Raven, Black-capped Chickadee, Tufted Titmouse, \
        White-breasted Nuthatch, Brown Creeper, Carolina Wren, House Wren, \
        Golden-crowned Kinglet, Eastern Bluebird, American Robin, Hermit Thrush, \
        Cedar Waxwing, European Starling, Northern Cardinal, American Goldfinch, \
        House Finch, Purple Finch, Pine Siskin, Chipping Sparrow, Field Sparrow, \
        Song Sparrow, Swamp Sparrow, White-throated Sparrow, Dark-eyed Junco, \
        Eastern Towhee, Red-winged Blackbird, Common Grackle, Brown-headed Cowbird, \
        Baltimore Oriole, Yellow Warbler, Yellow-rumped Warbler, Common Yellowthroat, \
        American Redstart, Magnolia Warbler, Black-throated Green Warbler, Ovenbird, \
        Northern Waterthrush, Scarlet Tanager, Rose-breasted Grosbeak, Indigo Bunting, \
        Ring-billed Gull, Herring Gull, Snowy Owl, Great Horned Owl, Barred Owl, \
        Eastern Screech-Owl, American Coot, Killdeer.
        """

    static func makeWhisperKit(model: String) async throws -> WhisperKit {
        eprint("Loading WhisperKit model \(model) (first run downloads it)...")
        let config = WhisperKitConfig(model: model, verbose: false, logLevel: .error)
        let whisperKit = try await WhisperKit(config)
        eprint("ASR ready.")
        return whisperKit
    }

    /// Status messages go to stderr so stdout stays clean for scripting
    /// (the backend calls this CLI and reads stdout).
    static func eprint(_ line: String) {
        fputs(line + "\n", stderr)
    }

    /// Decoding options with the birding vocabulary as the conditioning prompt.
    /// (Property mutation instead of init args so this survives SDK changes.)
    static func decodingOptions(
        tokenizer: (any WhisperTokenizer)?, promptTokensFrom prompt: String? = nil
    ) -> DecodingOptions {
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = "en"
        options.chunkingStrategy = .vad
        options.wordTimestamps = false
        if let tokenizer, let prompt {
            // Whisper conditions on the tail of the prompt; keep it short.
            options.promptTokens = Array(tokenizer.encode(text: prompt).suffix(220))
        }
        return options
    }
}