//
//  ViewController.swift
//  CameraApp
//
//  Created by Ravi Shankar on 8/7/18.
//  Copyright © 2018 Ravi Shankar. All rights reserved.
//

import UIKit

class ViewController: UIViewController, CameraControllerDelegate {

    @IBOutlet var cameraButton: UIButton!
    @IBOutlet var imageView: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        imageView.contentMode = .scaleAspectFit
        imageView.image = UIImage(named: "picture.png")
        
        cameraButton.layer.cornerRadius = 5
        
    }
    

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        
    }
    
    //param - CameraControllerDelegate methods
    func capturedImage(image: UIImage) {
        DispatchQueue.main.async {
            self.imageView.image = image
        }
    }
    
    //Open camera action method
    @IBAction func cameraButtonAction(_ sender: Any) {
        performSegue(withIdentifier: "cameraSegue", sender: self)
    }
    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "cameraSegue" {
            let cameraController: CameraController = segue.destination as! CameraController
            cameraController.delegate = self
        }
    }
}

