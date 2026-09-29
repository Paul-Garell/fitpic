import UIKit

// MARK: - Committing a run

extension ClosetStore {

    struct CommitResult {
        var created = 0
        var matched = 0
        var discarded = 0
    }

    /// Applies the user's decisions for every proposal in `run`.
    @discardableResult
    func commit(_ run: PipelineRun) -> CommitResult {
        var result = CommitResult()
        for proposal in run.proposals {
            switch proposal.decision {
            case .discard:
                result.discarded += 1

            case .match(let itemID):
                recordSighting(itemID: itemID, fitPicID: run.fitPicID, featurePrint: proposal.featurePrint)
                // Backfill a thumbnail for items that never got one.
                if var item = item(id: itemID), item.thumbnailPath == nil, let crop = proposal.crop {
                    item.thumbnailPath = ImageStorage.shared.save(ClosetImaging.flattenedOnWhite(crop), subdirectory: "Closet")
                    update(item)
                }
                result.matched += 1

            case .createNew:
                let thumbnail = proposal.crop.flatMap {
                    ImageStorage.shared.save(ClosetImaging.flattenedOnWhite($0), subdirectory: "Closet")
                }
                var item = ClosetItem(from: proposal.garment, thumbnailPath: thumbnail, featurePrint: proposal.featurePrint)
                if let fitPicID = run.fitPicID { item.wornOn = [fitPicID] }
                add(item)
                result.created += 1
            }
        }
        run.status = .committed
        return result
    }
}
