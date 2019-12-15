//
//  AppDelegate.swift
//  AVCamFilterMacOS
//
//  Created by Jake Van Alstyne on 11/15/19.
//  Copyright © 2019 Jake Van Alstyne. All rights reserved.
//

import Cocoa
import SwiftUI

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
    let identifier = NSStoryboard.SceneIdentifier("MainWindowController")
    guard let windowController = storyboard.instantiateController(withIdentifier: identifier) as? NSWindowController else {
      fatalError("Why cant I find PopoverViewController? - Check Main.storyboard")
    }
    windowController.showWindow(self)
  }
}
