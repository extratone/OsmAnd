//
//  OABaseBottomSheetViewController.h
//  OsmAnd
//
//  Created by Paul on 28.10.2020.
//  Copyright © 2020 OsmAnd. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface OABaseBottomSheetViewController : UIViewController

@property (weak, nonatomic) IBOutlet UIButton *leftButton;
@property (weak, nonatomic) IBOutlet UIButton *rightButton;
@property (weak, nonatomic) IBOutlet UIImageView *leftIconView;
@property (weak, nonatomic) IBOutlet UILabel *titleView;
@property (weak, nonatomic) IBOutlet UIButton *closeButton;
@property (weak, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet UIView *bottomSheetView;

- (void) presentInViewController:(UIViewController *)viewController;

@property (nonatomic, readonly) CGFloat initialHeight;

- (CGFloat) getHeaderViewHeight;
- (void) onRightButtonPressed;

@end

