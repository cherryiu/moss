import CoreText
import Foundation

enum MossFonts {
    static let pixelPostScriptName = "BoldsPixels"

    static func registerBundledFonts() {
        let fontURL = Bundle.main.url(forResource: "BoldPixels", withExtension: "ttf")
            ?? Bundle.module.url(forResource: "BoldPixels", withExtension: "ttf")

        guard let fontURL else {
            assertionFailure("BoldPixels.ttf is missing from the Moss bundle")
            return
        }

        var registrationError: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(
            fontURL as CFURL,
            .process,
            &registrationError
        )

        // Core Text reports an error when the same font has already been registered
        // in this process, which is harmless during SwiftUI preview/app relaunches.
        if !didRegister,
           let error = registrationError?.takeRetainedValue() {
            let nsError = error as Error as NSError
            let alreadyRegistered = nsError.domain == kCTFontManagerErrorDomain as String
                && nsError.code == CTFontManagerError.alreadyRegistered.rawValue
            if !alreadyRegistered {
                assertionFailure("Could not register BoldPixels: \(error)")
            }
        }
    }
}
