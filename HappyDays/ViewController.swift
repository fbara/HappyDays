//
//  ViewController.swift
//  HappyDays
//
//  Created by Frank Bara on 11/24/18.
//  Copyright © 2018 BaraLabs. All rights reserved.
//

import UIKit
import AVFoundation
import Speech
import Photos

class ViewController: UIViewController {

    @IBOutlet weak var helpLabel: UILabel!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    @IBAction func requestPermissions(_ sender: Any) {
        requestPhotosPermissions()
    }
    

    //MARK: - Request Permissions
    
    func requestPhotosPermissions() {
        PHPhotoLibrary.requestAuthorization { [unowned self] authStatus in
            DispatchQueue.main.sync {
                if authStatus == .authorized {
                    self.requestRecordPermissions()
                } else {
                    self.helpLabel.text = "Photos permission was declined; please enable it in settings then tap Continue again."
                }
            }
        }
    }
    
    func requestRecordPermissions() {
        AVAudioSession.sharedInstance().requestRecordPermission() {
            [unowned self] allowed in
            DispatchQueue.main.sync {
                if allowed {
                    self.requestTranscribePermissions()
                } else {
                    self.helpLabel.text = "Recording permission was declined. Please enable it in Settings then tap Continue again."
                }
            }
        }
    }
    
    func requestTranscribePermissions() {
        SFSpeechRecognizer.requestAuthorization { [unowned self] authStatus in
            DispatchQueue.main.sync {
                if authStatus == .authorized {
                    self.authorizationComplete()
                } else {
                    self.helpLabel.text = "Photos permission was declined; please enable it in settings then tap Continue again."
                }
            }
        }
    }
    
    func authorizationComplete() {
        dismiss(animated: true, completion: nil)
    }
}

