//
//  PPEditorBridge.swift
//  PurePets
//
//  Created by ChatGPT.
//

import Foundation
import UIKit

#if canImport(HXPHPicker)
import HXPHPicker
#elseif canImport(HXPhotoPicker)
import HXPhotoPicker
#endif

#if canImport(HXPHPicker) || canImport(HXPhotoPicker)

public extension Notification.Name {
    static let PPEditorBridgeDidFinish = Notification.Name("PPEditorBridgeDidFinish")
    static let PPEditorBridgeDidCancel = Notification.Name("PPEditorBridgeDidCancel")
}

@objc public class PPEditorBridge: NSObject {

    @objc public var useArabic: Bool = false

    // MARK: Present Editor (Objective-C entry point)
    @objc(presentEditorFromViewController:withImage:useArabic:)
    public func presentEditor(
        from viewController: UIViewController,
        with image: UIImage,
        useArabic: Bool
    ) {
        // Language bundle
        PhotoManager.shared.createLanguageBundle(
            languageType: useArabic ? .arabic : .english
        )

        // Editor configuration
        var config = EditorConfiguration()
        config.languageType = useArabic ? .arabic : .english
        config.indicatorType = .circle
        config.modalPresentationStyle = .fullScreen
        
        // Convert image → EditorAsset
        let asset = EditorAsset(type: .image(image))

        // Build editor VC with delegate
        let editorVC = EditorViewController(asset, config: config)
        editorVC.delegate = self

        let nav = UINavigationController(rootViewController: editorVC)
        nav.modalPresentationStyle = .fullScreen

        viewController.present(nav, animated: true)
    }
}


// MARK: - Correct Editor Delegate Implementation
extension PPEditorBridge: EditorViewControllerDelegate {

    // Editor Finished
    public func editorViewController(
        _ editorViewController: EditorViewController,
        didFinish asset: EditorAsset
    ) {
        var finalImage: UIImage? = nil
        var finalURL: URL? = nil

        switch asset.result {
            
        case .image(let result, _):
            // This is the real final edited image
            finalImage = result.image
            finalURL = result.urlConfig.url

        case .video(let result, _):
            // Videos return a cover + file URL
            finalImage = result.coverImage
            finalURL = result.urlConfig.url

        case .none:
            break
        }

        // Post result to Objective-C
        var info: [AnyHashable: Any] = [:]

        if let img = finalImage { info["image"] = img }
        if let u = finalURL { info["url"] = u as NSURL }

        NotificationCenter.default.post(
            name: .PPEditorBridgeDidFinish,
            object: nil,
            userInfo: info
        )

        editorViewController.dismiss(animated: true)
    }

    // Editor Cancelled
    public func editorViewController(
        didCancel editorViewController: EditorViewController
    ) {
        NotificationCenter.default.post(
            name: .PPEditorBridgeDidCancel,
            object: nil
        )
        editorViewController.dismiss(animated: true)
    }
}

#else

public extension Notification.Name {
    static let PPEditorBridgeDidFinish = Notification.Name("PPEditorBridgeDidFinish")
    static let PPEditorBridgeDidCancel = Notification.Name("PPEditorBridgeDidCancel")
}

@objc public class PPEditorBridge: NSObject {
    @objc public var useArabic: Bool = false

    @objc(presentEditorFromViewController:withImage:useArabic:)
    public func presentEditor(
        from viewController: UIViewController,
        with image: UIImage,
        useArabic: Bool
    ) {
        _ = viewController
        _ = image
        _ = useArabic
        NotificationCenter.default.post(name: .PPEditorBridgeDidCancel, object: nil)
    }
}

#endif
