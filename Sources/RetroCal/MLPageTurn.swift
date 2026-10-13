import AppKit
import QuartzCore

// Page-turn animation (UM-07, VIS-12). The classic Mac Calendar only animated it for two-finger swipes; arrow buttons and keyboard
// jump directly. This is a reconstruction (no recorded reference): the old page swings out on its left hinge with
// perspective and a fading shadow; going back, the previous page swings down onto the current one. ~0.4 s.

private final class MLTurnOverlay: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }          // never intercepts the mouse
}

extension MLMainView {
    /// Pixel snapshot of the whole content area.
    func snapshotImage() -> CGImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }
}

extension MLController {
    func turnPage(forward: Bool) {
        guard !turning, let root = window?.contentView, let old = main.snapshotImage() else { step(forward ? 1 : -1); return }
        turning = true
        step(forward ? 1 : -1)
        main.displayIfNeeded()
        guard let new = main.snapshotImage() else { turning = false; return }

        let overlay = MLTurnOverlay(frame: main.frame)
        overlay.wantsLayer = true
        root.addSubview(overlay, positioned: .above, relativeTo: main)
        let host = overlay.layer!
        host.masksToBounds = true
        var persp = CATransform3DIdentity; persp.m34 = -1.0 / 2600
        host.sublayerTransform = persp
        let size = overlay.bounds.size

        func page(_ img: CGImage) -> CALayer {
            let l = CALayer()
            l.bounds = CGRect(origin: .zero, size: size)
            l.anchorPoint = CGPoint(x: 0, y: 0.5); l.position = CGPoint(x: 0, y: size.height / 2)
            l.contents = img; l.contentsGravity = .resize
            l.shadowColor = NSColor.black.cgColor; l.shadowOpacity = 0.45; l.shadowRadius = 14; l.shadowOffset = .zero
            return l
        }
        let shade = CALayer(); shade.frame = CGRect(origin: .zero, size: size); shade.backgroundColor = NSColor.black.cgColor; shade.opacity = 0
        let under = page(forward ? new : old), top = page(forward ? old : new)
        under.shadowOpacity = 0
        host.addSublayer(under); host.addSublayer(shade); host.addSublayer(top)

        // forward: the old page swings away to the left (0 → -90°) and the page under it lights up;
        // back:    the previous page swings in from the left (-90° → 0) and darkens the page below as it lands.
        let dur = 0.45
        let angle: CGFloat = -(.pi / 2)
        let from = forward ? 0 : angle, to = forward ? angle : 0
        let shadeFrom: Float = forward ? 0.4 : 0, shadeTo: Float = forward ? 0 : 0.4
        top.transform = CATransform3DMakeRotation(from, 0, 1, 0); shade.opacity = shadeFrom
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in overlay.removeFromSuperview(); self?.turning = false }
        let rot = CABasicAnimation(keyPath: "transform.rotation.y")
        rot.fromValue = from; rot.toValue = to; rot.duration = dur; rot.fillMode = .forwards; rot.isRemovedOnCompletion = false
        rot.timingFunction = CAMediaTimingFunction(name: forward ? .easeIn : .easeOut)
        top.add(rot, forKey: "turn")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = shadeFrom; fade.toValue = shadeTo; fade.duration = dur; fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
        shade.add(fade, forKey: "fade")
        CATransaction.commit()
    }
}
