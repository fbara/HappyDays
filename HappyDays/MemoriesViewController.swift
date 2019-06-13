//
//  MemoriesViewController.swift
//  HappyDays
//
//  Created by Frank Bara on 11/27/18.
//  Copyright © 2018 BaraLabs. All rights reserved.
//

import UIKit
import AVFoundation
import Speech
import Photos

class MemoriesViewController: UICollectionViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UICollectionViewDelegateFlowLayout, AVAudioRecorderDelegate {
    
    var memories = [URL]()
    var activeMemory, recordingURL: URL!
    var audioRecorder: AVAudioRecorder?
    

    override func viewDidLoad() {
        super.viewDidLoad()

        checkPermissions()
        loadMemories()
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addTapped))
        
        recordingURL = getDocumentsDirectory().appendingPathComponent("recording.m4a")
        
    }
    
    // MARK: - Request Permissions
    
    func checkPermissions() {
        // check status for all three permissions
        let photosAuthorized = PHPhotoLibrary.authorizationStatus() == .authorized
        let recordingAuthorized = AVAudioSession.sharedInstance().recordPermission == .granted
        let transcribedAuthorized = SFSpeechRecognizer.authorizationStatus() == .authorized
        
        // make a single boolean out of all three
        let authorized = photosAuthorized && recordingAuthorized && transcribedAuthorized
        
        // if we're missing one, show the first run screen
        if authorized == false {
            if let vc = storyboard?.instantiateViewController(withIdentifier: "FirstRun") {
                navigationController?.present(vc, animated: true, completion: nil)
            }
        }
    }

    // MARK: - Helper Functions
    
    func getDocumentsDirectory() -> URL {
        
        //first, find document directory
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        
        return documentsDirectory
    }

    func loadMemories() {
        //remove existing memories to avoid duplicates.
        memories.removeAll()
        
        //attempt to load all the memories in our documents directory
        // we need to call with try? because it might fail if there's missing permissions.
        guard let files = try? FileManager.default.contentsOfDirectory(at: getDocumentsDirectory(), includingPropertiesForKeys: nil, options: []) else { return }
        
        //loop over every file found.
        for file in files {
            let fileName = file.lastPathComponent
            
            // check it ends with ".thumb" so we don't count each memory more than once
            if fileName.hasSuffix(".thumb") {
                // get the root name of the memory (i.e., without its path extension)
                let noExtention = fileName.replacingOccurrences(of: ".thumb", with: "")
                
                // create a full path from the memory
                let memoryPath = getDocumentsDirectory().appendingPathComponent(noExtention)
                // add it to our array
                memories.append(memoryPath)
            }
        }
        
        // reload the list of memories (from second section)
        collectionView?.reloadSections(IndexSet(integer: 1))
    }
    
    func saveNewMemory(image: UIImage) {
        // create a unique name for this memory
        let memoryName = "memory-\(Date().timeIntervalSince1970)"
        
        // use the unique name to create filenames for the full-size image and the thumbnail
        let imageName = memoryName + ".jpg"
        let thumbnailName = memoryName + ".thumb"
        
        do {
            // create a URL where we can write the JPEG to
            let imagePath = getDocumentsDirectory().appendingPathComponent(imageName)
            
            // convert the UIImage into a JPEG data object
            if let jpegData = image.jpegData(compressionQuality: 0.8) {
                // write that data to the URL we created
                try jpegData.write(to: imagePath, options: [.atomicWrite])
            }
            
            if let thumbnail = resize(image: image, to: 200) {
                let imagePath = getDocumentsDirectory().appendingPathComponent(thumbnailName)
                if let jpegData = thumbnail.jpegData(compressionQuality: 0.8) {
                    try jpegData.write(to: imagePath, options: [.atomicWrite])
                }
            }
            
        } catch {
            print("Failed save to disk")
        }
    }
    
    func resize(image: UIImage, to width: CGFloat) -> UIImage? {
        // calculate how much we need to bring the width down to match our target size
        let scale = width / image.size.width
        
        // bring the height down by the same amount so that the aspect ratio is preserved
        let height = image.size.width * scale
        
        // create a new image context we can draw into
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), false, 0)
        
        // draw the original image into the context
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // pull out the resized version
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        
        // end the context so UIKit can clean up
        UIGraphicsEndImageContext()
        
        // send it back to the caller
        return newImage
        
    }
    
    func imageURL(for memory: URL) -> URL {
        return memory.appendingPathExtension("jpg")
    }
    
    func thumbnailURL(for memory: URL) -> URL {
        return memory.appendingPathExtension("thumb")
    }
    
    func audioURL(for memory: URL) -> URL {
        return memory.appendingPathExtension("m4a")
    }
    
    func transcriptionURL(for memory: URL) -> URL {
        return memory.appendingPathExtension("txt")
    }
    
    
    // MARK: - Delegate Functions
    
    @objc func addTapped() {
        let vc = UIImagePickerController()
        vc.modalPresentationStyle = .formSheet
        vc.delegate = self
        navigationController?.present(vc, animated: true, completion: nil)
    }
    
    // MARK: - Gesture and Recording
    
    
    @objc func memoryLongPress(sender: UILongPressGestureRecognizer) {
        // called when a long press has started or ended
        
        // convert the gesture recognizer’s view property to a MemoryCell,
        // then we can pass that to the indexPath() method of our collection view.
        if sender.state == .began {
            let cell = sender.view as! MemoryCell
            
            if let index = collectionView?.indexPath(for: cell) {
                activeMemory = memories[index.row]
                recordMemory()
            }
        } else if sender.state == .ended {
            finishRecording(success: true)
        }
    }
    
    func recordMemory() {
        // perform mic recording
        
        // Set the background color to red so the user knows their microphone is recording.
        collectionView?.backgroundColor = UIColor(red: 0.5, green: 0, blue: 0, alpha: 1)
        
        // this just saves me writing AVAudioSession.sharedInstance() everywhere
        let recordingSession = AVAudioSession.sharedInstance()
        
        do {
            // configure the session for recording and playback through the speaker
            try recordingSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try recordingSession.setActive(true, options: .init())
            
            // set up a high-quality recording session
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            // create the audio recording and assign ourselves as the delegate
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
        } catch let error {
            // failed to record
            print("Failed to record: \(error).")
            finishRecording(success: false)
        }
    }
    
    func finishRecording(success: Bool) {
        // mic recording has finished
        collectionView?.backgroundColor = UIColor.darkGray
        
        audioRecorder?.stop()
        
        if success {
            do {
                //create a file URL out of the active memory URL plus “m4a”
                let memoryAudioURL = activeMemory.appendingPathExtension("m4a")
                let fm = FileManager.default
                
                //If a recording already exists there, we need to delete it because you can’t move a file over one that already exists
                if fm.fileExists(atPath: memoryAudioURL.path) {
                    try fm.removeItem(at: memoryAudioURL)
                }
                
                //Move our recorded file (stored at the URL we put in recordingURL) into the memory’s audio URL
                try fm.moveItem(at: recordingURL, to: memoryAudioURL)
                
                //Start the transcription process
                transcribeAudio(memory: activeMemory)
            } catch let error {
                print("Failure finishing recording: \(error)")
            }
        }
    }
    
    
    /// Handles transcribing the narration into text and linking that to the memory.
    /// - Parameter memory: Root path to memory location of audio recording.
    func transcribeAudio(memory: URL) {
        // get paths to where the audio is, and where the transcription should be
        let audio = audioURL(for: memory)
        let transcription = transcriptionURL(for: memory)
        
        // create a new recognizer and point it at our audio
        let recognizer = SFSpeechRecognizer()
        let request = SFSpeechURLRecognitionRequest(url: audio)
        
        // start recognition
        recognizer?.recognitionTask(with: request, resultHandler: { [unowned self] (result, error) in
            // abort if we didn't get any transcription back
            guard let result = result else {
                print("There was an error: \(error!).")
                return
            }
            
            // if we got the final transcription back, we need to write it to disk
            if result.isFinal {
                // pull out the best transcription
                let text = result.bestTranscription.formattedString
                // ...and write it to disk at the correct filename for this memory.
                do {
                    try text.write(to: transcription, atomically: true, encoding: String.Encoding.utf8)
                } catch {
                    print("Failed to save transcription.")
                }
            }
        })

    }
    
    
    // MARK: - UIImagePicker Functions
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        if let possibleImage = info[.originalImage] as? UIImage{
            saveNewMemory(image: possibleImage)
            loadMemories()
        }
    }
    
    // MARK: - CollectionView Functions
    
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if section == 0 {
            return 0
        } else {
            return memories.count
        }
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // dequeue a cell, pull out the memory it matches, load a UIImage for the thumbnail of that memory, then put it into the cell’s image view
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Memory", for: indexPath) as! MemoryCell
        
        let memory = memories[indexPath.row]
        let imageName = thumbnailURL(for: memory).path
        let image = UIImage(contentsOfFile: imageName)
        cell.imageView.image = image
        
        // check for the gesture recognizer and add border to the cell
        if cell.gestureRecognizers == nil {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(memoryLongPress))
            recognizer.minimumPressDuration = 0.25
            cell.addGestureRecognizer(recognizer)
        }
        
        cell.layer.borderColor = UIColor.white.cgColor
        cell.layer.borderWidth = 3
        cell.layer.cornerRadius = 10
        
        return cell
    }
    
    override func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        // make search bar header work
        return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "Header", for: indexPath)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        if section == 1 {
            return CGSize.zero
        } else {
            return CGSize(width: 0, height: 50)
        }
    }
    
    // MARK: - Audio Recorder Delegate
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // catch when the recording got terminated by the system, e.g. if a phone call came in
        if !flag {
            finishRecording(success: false)
        }
    }
}
