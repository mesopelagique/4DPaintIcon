//
//  XcodeManager.swift
//  XcoatOfPaint
//
//  Created by Christian Lobach on 25.04.21.
//

import Cocoa

struct RecoveryAction {
    let title: String
    let action: () -> Void
}

struct XcodeManagerError: LocalizedError {

    fileprivate enum ErrorType {
        case needsToChangeInGetInfo
        case needsToRemoveInGetInfo
        case iconChangeFailed
    }

    fileprivate var errorType: ErrorType

    var recoveryAction: RecoveryAction? = nil

    var failureReason: String? {
        switch errorType {
        case .needsToChangeInGetInfo, .needsToRemoveInGetInfo:
            return "If you have installed 4D from the App Store, this app doesn't have enough permissions to change the app icon autimatically.\nYou can change or remove the icon manually via the \"Get Info\" dialog."
        default:
            return nil
        }
    }

    var recoverySuggestion: String? {
        switch errorType {
        case .needsToChangeInGetInfo:
            return "Select the existing icon in the top of the \"4D Info\" dialog and press ⌘ + V."
        case .needsToRemoveInGetInfo:
            return "Click on the icon in the \"4D Info\" dialog and press the delete key on your keyboard."
        default:
            return nil
        }
    }
}

class XcodeManager {

    var xcodeURL: URL?

    var xcodeIcon: NSImage? {
        iconFromAssetCatalog ?? iconFromICNS
    }

    private var iconFromICNS: NSImage? {
        guard let icnsURL = xcodeURL?.appendingPathComponent("Contents/Resources/4D.icns"),
              let betaIcnsURL = xcodeURL?.appendingPathComponent("Contents/Resources/4D-server.icns")
        else { return nil }
        let data = (try? Data(contentsOf: icnsURL)) ?? (try? Data(contentsOf: betaIcnsURL))
        let image = data.flatMap(NSImage.init(data:))
        return image
    }

    var iconFromAssetCatalog: NSImage? {
        guard let path = xcodeURL?.appendingPathComponent("Contents/Resources/Assets.car").path else { return nil }
        let catalog = try? AssetsCatalog(path: path)
        let imageSet = catalog?.imageSets.first(where: { $0.name == "4D" || $0.name == "4D-server" })
        let mutableData = NSMutableData()

        guard let bestImage = imageSet?.namedImages
                .sorted(by: { $0.size.width * CGFloat($0.scale) > $1.size.width * CGFloat($1.scale) })[1],
              let cgImage = bestImage
                ._rendition()
                .unslicedImage()?
                .takeUnretainedValue(),
              let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData,
                                                                 kUTTypePNG,
                                                                 1,
                                                                 nil)
                else { return nil}
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }

        let nsImage = NSImage(data: mutableData as Data)        
        return nsImage
    }

    func replaceIcon(with image: NSImage) throws {
        guard let xcodeURL = xcodeURL else { return }
        let iconChangeSuccessful = NSWorkspace.shared.setIcon(image,
                                                 forFile: xcodeURL.path,
                                                 options: [])
        if iconChangeSuccessful { return }

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.declareTypes([.fileURL], owner: nil)
        (xcodeURL as NSURL).write(to: pasteboard)

        throw XcodeManagerError(errorType: .needsToChangeInGetInfo,
                                recoveryAction: RecoveryAction(title: "Open \"4D Info\" dialog") {
            if NSPerformService("Finder/Show Info", pasteboard) {
                let rep = image.tiffRepresentation
                let generalPasteboard = NSPasteboard.general
                generalPasteboard.clearContents()
                generalPasteboard.setData(rep, forType: .tiff)
            }
        })
    }

    func restoreDefaultIcon() throws {
        guard let xcodeURL = xcodeURL else { return }
        let iconChangeSuccessful = NSWorkspace.shared.setIcon(nil,
                                                              forFile: xcodeURL.path,
                                                              options: [])
        if iconChangeSuccessful { return }

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.declareTypes([.fileURL], owner: nil)
        (xcodeURL as NSURL).write(to: pasteboard)
        
        throw XcodeManagerError(errorType: .needsToRemoveInGetInfo,
                                recoveryAction: RecoveryAction(title: "Open \"4D Info\" dialog") {
                                    NSPerformService("Finder/Show Info", pasteboard)
                                })
    }

}
