import Foundation
import Testing
@testable import MovingPaper

struct PhotosShuffleFailureTests {

    @Test func accessDeniedExplainsSettings() {
        let failure = PhotosShuffleFailure.accessDenied
        #expect(failure.alertTitle == "Photos Access Needed")
        #expect(failure.alertMessage.contains("System Settings"))
    }

    @Test func emptyLibraryDoesNotAskForPermission() {
        let failure = PhotosShuffleFailure.noVideos
        #expect(failure.alertTitle == "No Videos Found")
        #expect(failure.alertMessage.contains("Photos library"))
        #expect(!failure.alertMessage.contains("System Settings"))
    }

    @Test func exportFailurePointsAtChooseFromPhotos() {
        let failure = PhotosShuffleFailure.exportFailed
        #expect(failure.alertTitle == "Couldn't Shuffle")
        #expect(failure.alertMessage.contains("Choose from Photos"))
    }
}
