/*
 * Copyright (c) 2022, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import Foundation
import PsiApi

/// Wraps `SettingsViewController` to conform to Swift protocols.
final class SettingsViewController_Swift: SettingsViewController,
                                          ChildViewControllerDismissedDelegate {
    
    func parentIsDimissed() {
        // Manually calls `settingsWillDismiss(withForceReconnect:)` delegate callback
        // if this view controller is a child of a parent container controller that is
        // dismissed. (e.g. a UINavigationController).
        self.settingsDelegate.settingsWillDismiss(withForceReconnect: false)
    }
    
}

// Adds conformance to`ChildViewControllerDismissedDelegate` to satisfy
// `NavigationController` child view controller requirements.
extension SkyRegionSelectionViewController: ChildViewControllerDismissedDelegate {
    
    public func parentIsDimissed() {
        // No-op.
    }
    
}

// Adds conformance to`ChildViewControllerDismissedDelegate` to satisfy
// `NavigationController` child view controller requirements.
extension SubscriptionViewController: ChildViewControllerDismissedDelegate {
    
    public func parentIsDimissed() {
        // No-op.
    }
    
}

// Adds conformance to`ChildViewControllerDismissedDelegate` to satisfy
// `NavigationController` child view controller requirements.
extension FeedbackViewController: ChildViewControllerDismissedDelegate {
    
    public func parentIsDimissed() {
        // No-op
    }
    
}

// Adds conformance to`ChildViewControllerDismissedDelegate` to satisfy
// `NavigationController` child view controller requirements.
extension LanguageSelectionViewController: ChildViewControllerDismissedDelegate {
    
    public func parentIsDimissed() {
        // No-op
    }
    
}
