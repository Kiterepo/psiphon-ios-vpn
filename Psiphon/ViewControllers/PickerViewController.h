/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import <UIKit/UIKit.h>


NS_ASSUME_NONNULL_BEGIN

@interface PickerViewController : UIViewController
  <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, readonly) NSLocale *locale;

/**
 * Index of item that is currently selected. Default value is 0.
 */
@property (nonatomic) NSUInteger selectedIndex;

@property (nonatomic, copy, nullable) void (^selectionHandler)(NSUInteger selectedIndex,
                                                              id _Nullable selectedItem,
                                                              PickerViewController *viewController);

/**
 * Default constructor for PickerViewController.
 * Subclasses should provide their own init methods, and not use this method.
 */
- (instancetype)initWithLabels:(NSArray<NSString *> *)pickerLabels
                     andImages:(NSArray<UIImage *> *_Nullable)pickerImages
                        locale:(NSLocale *)locale;

/**
 * To be implemented by subclasses to tell number of rows to the internal table view.
 * @note Subclasses should not call this method on super.
 */
- (NSUInteger)numberOfRows;

/**
 * To be implemented by subclasses to bind data to the cell that is going to be displayed
 * sometime soon.
 * @note Subclasses should not call this method on super.
 */
- (void)bindDataToCell:(UITableViewCell *)cell atRow:(NSUInteger)rowIndex;

/**
 * To be implemented by subclasses when a cell gets selected.
 * This delegate is called regardless of whether the selected row is different from current value
 * (i.e. `selectedIndex`).
 * @note Subclasses should not call this method on super.
 */
- (void)onSelectedRow:(NSUInteger)rowIndex;

/**
 * Table construction methods are called again to construct the table.
 */
- (void)reloadTableRows;

@end

NS_ASSUME_NONNULL_END
