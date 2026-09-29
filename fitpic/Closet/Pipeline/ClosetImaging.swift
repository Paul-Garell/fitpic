import UIKit
import CoreImage
import Vision

// MARK: - ClosetImaging

/// Pure image / Vision helpers for the cataloging pipeline.
/// Heavy work is `@concurrent` so it runs off the main actor.
nonisolated enum ClosetImaging {

    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    // MARK: Normalize

    /// Renders `image` upright (bakes in EXIF orientation) and downsamples so
    /// the longest edge is at most `maxDimension` pixels.
    @concurrent
    static func normalize(_ image: UIImage, maxDimension: Int) async -> CGImage? {
        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        let longest = max(pixelSize.width, pixelSize.height)
        let scale = longest > CGFloat(maxDimension) ? CGFloat(maxDimension) / longest : 1
        let target = CGSize(width: (pixelSize.width * scale).rounded(),
                            height: (pixelSize.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.cgImage
    }

    // MARK: Person segmentation

    struct SegmentationResult {
        let image: CGImage          // person only, cropped to instance extent
        let mask: CGImage?          // full-frame mask for display
        let instanceCount: Int
        let confidence: Float
    }

    @concurrent
    static func segmentPerson(_ cgImage: CGImage, background: PreprocessBackground) async throws -> SegmentationResult? {
        let handler = ImageRequestHandler(cgImage)
        let request = GeneratePersonInstanceMaskRequest()
        guard let observation = try await handler.perform(request),
              !observation.allInstances.isEmpty else { return nil }

        let maskedBuffer = try observation.generateMaskedImage(
            for: observation.allInstances,
            imageFrom: handler,
            croppedToInstancesExtent: true
        )
        var person = CIImage(cvPixelBuffer: maskedBuffer)
        switch background {
        case .transparent:
            break
        case .white:
            person = person.composited(over: CIImage(color: .white).cropped(to: person.extent))
        case .grey:
            person = person.composited(over: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: person.extent))
        }
        guard let personImage = ciContext.createCGImage(person, from: person.extent) else { return nil }

        let maskBuffer = try? observation.generateScaledMask(for: observation.allInstances, scaledToImageFrom: handler)
        let maskImage = maskBuffer.flatMap { buffer -> CGImage? in
            let ci = CIImage(cvPixelBuffer: buffer)
            return ciContext.createCGImage(ci, from: ci.extent)
        }

        return SegmentationResult(
            image: personImage,
            mask: maskImage,
            instanceCount: observation.allInstances.count,
            confidence: observation.confidence
        )
    }

    // MARK: Body pose

    @concurrent
    static func detectBodyPose(_ cgImage: CGImage) async throws -> [HumanBodyPoseObservation] {
        try await DetectHumanBodyPoseRequest().perform(on: cgImage)
    }

    /// All joints above `minConfidence`, in top-left pixel coordinates.
    static func joints(
        of observation: HumanBodyPoseObservation,
        imageSize: CGSize,
        minConfidence: Double
    ) -> [HumanBodyPoseObservation.JointName: CGPoint] {
        var result: [HumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (name, joint) in observation.allJoints() where Double(joint.confidence) >= minConfidence {
            result[name] = joint.location.toImageCoordinates(imageSize, origin: .upperLeft)
        }
        return result
    }

    // MARK: Crop regions

    struct CropDecision {
        let rect: CGRect
        let source: String
        let notes: [String]
    }

    /// Picks a crop rect for `garment` according to `strategy`, falling back to
    /// the full image (with a note) when the preferred strategy can't produce one.
    static func cropRect(
        for garment: DetectedGarment,
        strategy: CropStrategy,
        imageSize: CGSize,
        joints: [HumanBodyPoseObservation.JointName: CGPoint],
        padding: Double
    ) -> CropDecision {
        let full = CGRect(origin: .zero, size: imageSize)
        var notes: [String] = []

        func finalize(_ rect: CGRect, source: String) -> CropDecision {
            let padded = rect.insetBy(dx: -imageSize.width * padding, dy: -imageSize.height * padding)
            let clamped = padded.intersection(full).integral
            if clamped.width < 8 || clamped.height < 8 {
                notes.append("Crop collapsed after clamping (\(clamped)); using full image")
                return CropDecision(rect: full, source: "fullPerson (fallback)", notes: notes)
            }
            return CropDecision(rect: clamped, source: source, notes: notes)
        }

        switch strategy {
        case .fullPerson:
            return CropDecision(rect: full, source: "fullPerson", notes: [])

        case .modelBox:
            let b = garment.box
            if b.x + b.width > 1000 || b.y + b.height > 1000 {
                notes.append("Box overflows grid (x+w=\(b.x + b.width), y+h=\(b.y + b.height)); clamped. Model may be emitting x2/y2 instead of width/height.")
            }
            let rect = CGRect(
                x: CGFloat(b.x) / 1000 * imageSize.width,
                y: CGFloat(b.y) / 1000 * imageSize.height,
                width: CGFloat(b.width) / 1000 * imageSize.width,
                height: CGFloat(b.height) / 1000 * imageSize.height
            )
            if rect.width < imageSize.width * 0.03 || rect.height < imageSize.height * 0.03 {
                notes.append("Model box too small (\(b.width)x\(b.height) on 1000 grid); using full image")
                return CropDecision(rect: full, source: "fullPerson (fallback)", notes: notes)
            }
            return finalize(rect, source: "modelBox")

        case .bodyPose:
            if let rect = poseRegion(for: garment.category, joints: joints, imageSize: imageSize, notes: &notes) {
                return finalize(rect, source: "bodyPose(\(garment.category.rawValue))")
            }
            notes.append("Required joints missing for \(garment.category.rawValue); using full image")
            return CropDecision(rect: full, source: "fullPerson (fallback)", notes: notes)
        }
    }

    private static func poseRegion(
        for category: GarmentCategory,
        joints: [HumanBodyPoseObservation.JointName: CGPoint],
        imageSize: CGSize,
        notes: inout [String]
    ) -> CGRect? {
        func pts(_ names: [HumanBodyPoseObservation.JointName]) -> [CGPoint] {
            names.compactMap { joints[$0] }
        }
        let shoulders = pts([.leftShoulder, .rightShoulder])
        let hips = pts([.leftHip, .rightHip, .root])
        let knees = pts([.leftKnee, .rightKnee])
        let ankles = pts([.leftAnkle, .rightAnkle])
        let elbows = pts([.leftElbow, .rightElbow])
        let wrists = pts([.leftWrist, .rightWrist])
        let neck = joints[.neck]
        let nose = joints[.nose]

        // Torso width is the unit for all the heuristic margins below.
        let torso: CGFloat = {
            if shoulders.count == 2 { return max(abs(shoulders[0].x - shoulders[1].x), imageSize.width * 0.1) }
            return imageSize.width * 0.3
        }()
        if shoulders.count < 2 { notes.append("Only \(shoulders.count) shoulder joint(s); torso width estimated as 30% of image") }

        func bounds(_ points: [CGPoint], xMargin: CGFloat, top: CGFloat, bottom: CGFloat) -> CGRect? {
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max() else { return nil }
            return CGRect(x: minX - xMargin, y: top, width: (maxX - minX) + xMargin * 2, height: bottom - top)
        }

        switch category {
        case .top:
            guard !shoulders.isEmpty, !hips.isEmpty else { return nil }
            let top = min(neck?.y ?? .infinity, shoulders.map(\.y).min()!) - torso * 0.2
            let bottom = hips.map(\.y).max()! + torso * 0.15
            return bounds(shoulders + elbows + hips, xMargin: torso * 0.25, top: top, bottom: bottom)

        case .outerwear:
            guard !shoulders.isEmpty, !hips.isEmpty else { return nil }
            let top = min(neck?.y ?? .infinity, shoulders.map(\.y).min()!) - torso * 0.25
            let bottom = (hips + wrists).map(\.y).max()! + torso * 0.25
            return bounds(shoulders + elbows + wrists + hips, xMargin: torso * 0.25, top: top, bottom: bottom)

        case .bottom:
            let lower = ankles.isEmpty ? knees : ankles
            guard !hips.isEmpty, !lower.isEmpty else { return nil }
            if ankles.isEmpty { notes.append("No ankles; bottom crop ends at knees") }
            let top = hips.map(\.y).min()! - torso * 0.2
            let bottom = lower.map(\.y).max()! + torso * 0.15
            return bounds(hips + knees + ankles, xMargin: torso * 0.35, top: top, bottom: bottom)

        case .dress:
            let lower = ankles.isEmpty ? knees : ankles
            guard !shoulders.isEmpty, !lower.isEmpty else { return nil }
            let top = min(neck?.y ?? .infinity, shoulders.map(\.y).min()!) - torso * 0.2
            let bottom = lower.map(\.y).max()! + torso * 0.15
            return bounds(shoulders + hips + knees + ankles, xMargin: torso * 0.35, top: top, bottom: bottom)

        case .shoes:
            guard !ankles.isEmpty else { return nil }
            let top = ankles.map(\.y).min()! - torso * 0.3
            let bottom = ankles.map(\.y).max()! + torso * 0.5
            return bounds(ankles, xMargin: torso * 0.45, top: top, bottom: bottom)

        case .hat:
            guard let anchor = nose ?? neck else { return nil }
            let bottom = nose.map { $0.y } ?? (anchor.y - torso * 0.3)
            return CGRect(x: anchor.x - torso * 0.6, y: 0, width: torso * 1.2, height: max(bottom, torso * 0.3))

        case .bag, .accessory, .other:
            notes.append("No pose heuristic for \(category.rawValue); using full image")
            return nil
        }
    }

    // MARK: Cropping & features

    static func crop(_ cgImage: CGImage, to rect: CGRect) -> CGImage? {
        cgImage.cropping(to: rect)
    }

    @concurrent
    static func featurePrint(for cgImage: CGImage) async throws -> FeaturePrintObservation {
        try await GenerateImageFeaturePrintRequest().perform(on: cgImage)
    }

    // MARK: Debug overlays

    static let palette: [UIColor] = [.systemRed, .systemBlue, .systemGreen, .systemOrange,
                                     .systemPurple, .systemPink, .systemTeal, .systemYellow,
                                     .systemIndigo, .systemBrown]

    static func overlay(boxes: [(rect: CGRect, label: String)], on cgImage: CGImage) -> UIImage {
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
            let lineWidth = max(size.width / 200, 2)
            let font = UIFont.boldSystemFont(ofSize: max(size.width / 35, 12))
            for (index, box) in boxes.enumerated() {
                let color = palette[index % palette.count]
                color.setStroke()
                let path = UIBezierPath(rect: box.rect)
                path.lineWidth = lineWidth
                path.stroke()

                let text = "\(index) \(box.label)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let textSize = text.size(withAttributes: attrs)
                let origin = CGPoint(x: box.rect.minX, y: max(box.rect.minY - textSize.height, 0))
                color.setFill()
                ctx.fill(CGRect(origin: origin, size: CGSize(width: textSize.width + 8, height: textSize.height)))
                text.draw(at: CGPoint(x: origin.x + 4, y: origin.y), withAttributes: attrs)
            }
        }
    }

    static func overlay(
        joints: [HumanBodyPoseObservation.JointName: CGPoint],
        on cgImage: CGImage
    ) -> UIImage {
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let bones: [(HumanBodyPoseObservation.JointName, HumanBodyPoseObservation.JointName)] = [
            (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.neck, .root),
            (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle), (.nose, .neck)
        ]
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
            let radius = max(size.width / 120, 3)
            UIColor.systemGreen.setStroke()
            for (a, b) in bones {
                guard let p1 = joints[a], let p2 = joints[b] else { continue }
                let path = UIBezierPath()
                path.move(to: p1)
                path.addLine(to: p2)
                path.lineWidth = radius / 1.5
                path.stroke()
            }
            UIColor.systemYellow.setFill()
            for point in joints.values {
                ctx.cgContext.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                                     width: radius * 2, height: radius * 2))
            }
        }
    }

    /// Flattens transparency onto white so JPEG storage doesn't turn it black.
    static func flattenedOnWhite(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
    }
}
