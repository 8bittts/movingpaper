import Foundation
import Testing
@testable import MovingPaper

struct PhotosShuffleOutcomeTests {

    @Test func accessDeniedExplainsSettings() {
        let outcome = PhotosShuffleOutcome.accessDenied
        #expect(outcome.alertTitle == "Photos Access Needed")
        #expect(outcome.alertMessage?.contains("System Settings") == true)
    }

    @Test func emptyLibraryDoesNotAskForPermission() {
        let outcome = PhotosShuffleOutcome.noVideos
        #expect(outcome.alertTitle == "No Videos Found")
        #expect(outcome.alertMessage?.contains("Photos library") == true)
        #expect(outcome.alertMessage?.contains("System Settings") != true)
    }

    @Test func exportFailurePointsAtChooseFromPhotos() {
        let outcome = PhotosShuffleOutcome.exportFailed
        #expect(outcome.alertTitle == "Couldn't Shuffle")
        #expect(outcome.alertMessage?.contains("Choose from Photos") == true)
    }

    @Test func successHasNoAlert() {
        let url = URL(fileURLWithPath: "/tmp/clip.mp4")
        let outcome = PhotosShuffleOutcome.video(url)
        #expect(outcome.alertTitle == nil)
        #expect(outcome.alertMessage == nil)
    }
}
