//
//  OAMapInfoController.m
//  OsmAnd
//
//  Created by Alexey Kulish on 08/10/2017.
//  Copyright © 2017 OsmAnd. All rights reserved.
//

#import "OAMapInfoController.h"
#import "OAMapHudViewController.h"
#import "OsmAndApp.h"
#import "OARootViewController.h"
#import "OARoutingHelper.h"
#import "Localization.h"
#import "OAAutoObserverProxy.h"
#import "OAColors.h"
#import "OADayNightHelper.h"
#import "OASizes.h"
#import "OATextInfoWidget.h"
#import "OAMapWidgetRegistry.h"
#import "OAMapWidgetRegInfo.h"
#import "OAMapInfoWidgetsFactory.h"
#import "OANextTurnWidget.h"
#import "OALanesControl.h"
#import "OATopTextView.h"
#import "OAAlarmWidget.h"
#import "OARulerWidget.h"
#import "OATimeWidgetState.h"
#import "OABearingWidgetState.h"
#import "OACompassRulerWidgetState.h"
#import "OAUserInteractionPassThroughView.h"
#import "OAToolbarViewController.h"
#import "OADownloadMapWidget.h"
#import "OAWeatherToolbar.h"
#import "OAWeatherPlugin.h"
#import "OACompassModeWidgetState.h"
#import "OAFloatingButtonsHudViewController.h"
#import "OAMapLayers.h"
#import "OAWeatherLayerSettingsViewController.h"
#import "OASunriseSunsetWidget.h"
#import "OASunriseSunsetWidgetState.h"
#import "OAAltitudeWidget.h"
#import "OAMapRendererView.h"

#import "OsmAnd_Maps-Swift.h"

#define kWidgetsTopPadding 10.0

@implementation OATextState
@end

@interface OAMapInfoController () <OAWeatherLayerSettingsDelegate, OAWidgetPanelDelegate>

@end

@implementation OAMapInfoController
{
    OAMapHudViewController __weak *_mapHudViewController;

    OAMapWidgetRegistry *_mapWidgetRegistry;
    BOOL _expanded;
    BOOL _isBordersOfDownloadedMaps;
    OADownloadMapWidget *_downloadMapWidget;
    OAWeatherToolbar *_weatherToolbar;
    OAAlarmWidget *_alarmControl;
    OARulerWidget *_rulerControl;

    OAAppSettings *_settings;
    OADayNightHelper *_dayNightHelper;
    OAAutoObserverProxy* _framePreparedObserver;
    OAAutoObserverProxy* _locationServicesUpdateObserver;
    OAAutoObserverProxy* _mapZoomObserver;
    OAAutoObserverProxy* _mapSourceUpdatedObserver;

    NSTimeInterval _lastUpdateTime;
    int _themeId;

    NSArray<OABaseWidgetView *> *_widgetsToUpdate;
    NSTimer *_framePreparedTimer;
}

- (void)configureShadowForWidgets:(NSArray<UIView *> *)views
{
    for (UIView *view in views)
    {
        auto containerView = [[ShadowTransporentTouchesPassView alloc] init];
        containerView.layer.cornerRadius = 7;
        containerView.layer.shadowOpacity = 1;
        containerView.layer.shadowColor = [UIColor colorWithRed:0.0 green:0 blue:0 alpha:0.31].CGColor;
        containerView.layer.shadowOffset = CGSizeMake(0, 4);
        containerView.layer.shadowRadius = 7;
        containerView.layer.shouldRasterize = true;
        containerView.layer.rasterizationScale = [UIScreen mainScreen].scale;
        
        containerView.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview:containerView];
        [NSLayoutConstraint activateConstraints:@[
            [containerView.topAnchor constraintEqualToAnchor:view.topAnchor],
            [containerView.leftAnchor constraintEqualToAnchor:view.leftAnchor],
            [containerView.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
            [containerView.rightAnchor constraintEqualToAnchor:view.rightAnchor]
        ]];
    }
}

- (instancetype) initWithHudViewController:(OAMapHudViewController *)mapHudViewController
{
    self = [super init];
    if (self)
    {
        _settings = [OAAppSettings sharedManager];
        _dayNightHelper = [OADayNightHelper instance];

        _mapHudViewController = mapHudViewController;
        _topPanelController = [[OAWidgetPanelViewController alloc] initWithHorizontal:YES];
        _topPanelController.delegate = self;
        _topPanelController.specialPanelController = [[OAWidgetPanelViewController alloc] initWithHorizontal:YES special:YES];
        _topPanelController.specialPanelController.delegate = self;
        _leftPanelController = [[OAWidgetPanelViewController alloc] init];
        _leftPanelController.delegate = self;
        _bottomPanelController = [[OAWidgetPanelViewController alloc] initWithHorizontal:YES];
        _bottomPanelController.delegate = self;
        _rightPanelController = [[OAWidgetPanelViewController alloc] init];
        _rightPanelController.delegate = self;
        _mapHudViewController.view.clipsToBounds = NO;
        
        [mapHudViewController addChildViewController:_topPanelController];
        [mapHudViewController addChildViewController:_topPanelController.specialPanelController];
        [mapHudViewController addChildViewController:_leftPanelController];
        [mapHudViewController addChildViewController:_bottomPanelController];
        [mapHudViewController addChildViewController:_rightPanelController];

        [mapHudViewController.topWidgetsView addSubview:_topPanelController.view];
        [mapHudViewController.middleWidgetsView addSubview:_topPanelController.specialPanelController.view];
        [mapHudViewController.leftWidgetsView addSubview:_leftPanelController.view];
        [mapHudViewController.bottomWidgetsView addSubview:_bottomPanelController.view];
        [mapHudViewController.rightWidgetsView addSubview:_rightPanelController.view];
        
        [_topPanelController.view.layer addWidgetLayerDecoratorWithMask:kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner];
        [_topPanelController.specialPanelController.view.layer addWidgetLayerDecoratorWithMask:kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner];
        [_bottomPanelController.view.layer addWidgetLayerDecoratorWithMask:kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner];

        _topPanelController.view.translatesAutoresizingMaskIntoConstraints = NO;
        _topPanelController.specialPanelController.view.translatesAutoresizingMaskIntoConstraints = NO;
        _leftPanelController.view.translatesAutoresizingMaskIntoConstraints = NO;
        _bottomPanelController.view.translatesAutoresizingMaskIntoConstraints = NO;
        _rightPanelController.view.translatesAutoresizingMaskIntoConstraints = NO;

        [NSLayoutConstraint activateConstraints:@[
            [_topPanelController.view.topAnchor constraintEqualToAnchor:mapHudViewController.topWidgetsView.topAnchor constant:0.],
            [_topPanelController.view.leftAnchor constraintEqualToAnchor:mapHudViewController.topWidgetsView.leftAnchor constant:0.],
            [_topPanelController.view.bottomAnchor constraintEqualToAnchor:mapHudViewController.topWidgetsView.bottomAnchor constant:0.],
            [_topPanelController.view.rightAnchor constraintEqualToAnchor:mapHudViewController.topWidgetsView.rightAnchor constant:0.],

            [_topPanelController.specialPanelController.view.topAnchor constraintEqualToAnchor:mapHudViewController.middleWidgetsView.topAnchor constant:0.],
            [_topPanelController.specialPanelController.view.leftAnchor constraintEqualToAnchor:mapHudViewController.middleWidgetsView.leftAnchor constant:0.],
            [_topPanelController.specialPanelController.view.bottomAnchor constraintEqualToAnchor:mapHudViewController.middleWidgetsView.bottomAnchor constant:0.],
            [_topPanelController.specialPanelController.view.rightAnchor constraintEqualToAnchor:mapHudViewController.middleWidgetsView.rightAnchor constant:0.],

            [_leftPanelController.view.topAnchor constraintEqualToAnchor:mapHudViewController.leftWidgetsView.topAnchor constant:0.],
            [_leftPanelController.view.leftAnchor constraintEqualToAnchor:mapHudViewController.leftWidgetsView.leftAnchor constant:0.],
            [_leftPanelController.view.bottomAnchor constraintEqualToAnchor:mapHudViewController.leftWidgetsView.bottomAnchor constant:0.],
            [_leftPanelController.view.rightAnchor constraintEqualToAnchor:mapHudViewController.leftWidgetsView.rightAnchor constant:0.],

            [_bottomPanelController.view.topAnchor constraintEqualToAnchor:mapHudViewController.bottomWidgetsView.topAnchor constant:0.],
            [_bottomPanelController.view.leftAnchor constraintEqualToAnchor:mapHudViewController.bottomWidgetsView.leftAnchor constant:0.],
            [_bottomPanelController.view.bottomAnchor constraintEqualToAnchor:mapHudViewController.bottomWidgetsView.bottomAnchor constant:0.],
            [_bottomPanelController.view.rightAnchor constraintEqualToAnchor:mapHudViewController.bottomWidgetsView.rightAnchor constant:0.],

            [_rightPanelController.view.topAnchor constraintEqualToAnchor:mapHudViewController.rightWidgetsView.topAnchor constant:0],
            [_rightPanelController.view.leftAnchor constraintEqualToAnchor:mapHudViewController.rightWidgetsView.leftAnchor constant:0],
            [_rightPanelController.view.bottomAnchor constraintEqualToAnchor:mapHudViewController.rightWidgetsView.bottomAnchor constant:0],
            [_rightPanelController.view.rightAnchor constraintEqualToAnchor:mapHudViewController.rightWidgetsView.rightAnchor constant:0]
        ]];

        [_topPanelController didMoveToParentViewController:mapHudViewController];
        [_topPanelController.specialPanelController didMoveToParentViewController:mapHudViewController];
        [_leftPanelController didMoveToParentViewController:mapHudViewController];
        [_bottomPanelController didMoveToParentViewController:mapHudViewController];
        [_rightPanelController didMoveToParentViewController:mapHudViewController];
        
        [self configureShadowForWidgets:@[mapHudViewController.topWidgetsView,
                                          mapHudViewController.middleWidgetsView,
                                          mapHudViewController.leftWidgetsView,
                                          mapHudViewController.rightWidgetsView,
                                          mapHudViewController.bottomWidgetsView]];

        _mapWidgetRegistry = [OAMapWidgetRegistry sharedInstance];
        _expanded = NO;
        _themeId = -1;

        [self registerAllControls];
        [self recreateControls];
        
        _framePreparedObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                           withHandler:@selector(onMapRendererFramePrepared)
                                                            andObserve:[OARootViewController instance].mapPanel.mapViewController.framePreparedObservable];
        
        _locationServicesUpdateObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                                    withHandler:@selector(onLocationServicesUpdate)
                                                                     andObserve:[OsmAndApp instance].locationServices.updateObserver];
        
        _mapZoomObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                     withHandler:@selector(onMapZoomChanged:withKey:andValue:)
                                                      andObserve:[OARootViewController instance].mapPanel.mapViewController.zoomObservable];
        
        _mapSourceUpdatedObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                     withHandler:@selector(onMapSourceUpdated)
                                                      andObserve:[OARootViewController instance].mapPanel.mapViewController.mapSourceUpdatedObservable];
    }
    return self;
}

- (void) updateRuler {
    dispatch_async(dispatch_get_main_queue(), ^{
        [_rulerControl updateInfo];
    });
}

- (void) execOnDraw
{
    _lastUpdateTime = CACurrentMediaTime();
    __weak OAMapInfoController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf onDraw];
    });
}

- (void) onMapRendererFramePrepared
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (_framePreparedTimer)
            [_framePreparedTimer invalidate];
        
        _framePreparedTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(execOnDraw) userInfo:nil repeats:NO];
    });
    if (CACurrentMediaTime() - _lastUpdateTime > 1.0)
        [self execOnDraw];

    // Render the ruler more often
    [self updateRuler];
}

- (void) onRightWidgetSuperviewLayout
{
    [self execOnDraw];
}

- (void) onMapSourceUpdated
{
    [self execOnDraw];
    [self updateRuler];
}

- (void) onLocationServicesUpdate
{
    [self updateCurrentLocationAddress];
    [self updateInfo];
}

- (void) onDraw
{
    [self updateColorShadowsOfText];
    [_mapWidgetRegistry updateInfo:[_settings.applicationMode get] expanded:_expanded];
    for (OABaseWidgetView *widget in _widgetsToUpdate)
    {
        [widget updateInfo];
    }
}

- (void) updateCurrentLocationAddress
{
    [_mapHudViewController updateCurrentLocationAddress];
}

- (void) updateInfo
{
    __weak OAMapInfoController *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf onDraw];
    });
}

- (void) updateColorShadowsOfText
{
    OARoutingHelper *routingHelper = [OARoutingHelper sharedInstance];
    
    BOOL transparent = [_settings.transparentMapTheme get];
    BOOL nightMode = _settings.nightMode;
    BOOL following = [routingHelper isFollowingMode];
    
    int calcThemeId = (transparent ? 4 : 0) | (nightMode ? 2 : 0) | (following ? 1 : 0);
    if (_themeId != calcThemeId) {
        _themeId = calcThemeId;
        OATextState *state = [self calculateTextState];
        for (OAMapWidgetInfo *widgetInfo in [_mapWidgetRegistry getAllWidgets])
        {
            [widgetInfo.widget updateColors:state];
        }

        for (OAMapWidgetInfo *widgetInfo in [_mapWidgetRegistry getWidgetsForPanel:OAWidgetsPanel.leftPanel])
        {
            [self updateColors:state sideWidget:widgetInfo.widget];
        }

        for (OAMapWidgetInfo *widgetInfo in [_mapWidgetRegistry getWidgetsForPanel:OAWidgetsPanel.rightPanel])
        {
            [self updateColors:state sideWidget:widgetInfo.widget];
        }
    }
}

- (void)configureLayerWidgets:(BOOL)hasTopWidgets
{
    if (hasTopWidgets) {
        CACornerMask maskedCorners = kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
        [_rightPanelController.view.layer addWidgetLayerDecoratorWithMask:maskedCorners];
        [_leftPanelController.view.layer addWidgetLayerDecoratorWithMask:maskedCorners];
    }
    else
    {
        if ([OAUtilities isLandscapeIpadAware])
        {
            CACornerMask maskedCorners = kCALayerMaxXMaxYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMinXMinYCorner;
            [_rightPanelController.view.layer addWidgetLayerDecoratorWithMask:maskedCorners];
            [_leftPanelController.view.layer addWidgetLayerDecoratorWithMask:maskedCorners];
        }
        else
        {
            [_rightPanelController.view.layer addWidgetLayerDecoratorWithMask:kCALayerMinXMaxYCorner | kCALayerMinXMinYCorner];
            [_leftPanelController.view.layer addWidgetLayerDecoratorWithMask:kCALayerMaxXMaxYCorner | kCALayerMaxXMinYCorner];
        }
    }
}

- (void) layoutWidgets
{
    BOOL portrait = ![OAUtilities isLandscape];

    BOOL hasTopWidgets = [_topPanelController hasWidgets];
    BOOL hasTopSpecialWidgets = [_topPanelController.specialPanelController hasWidgets];
    BOOL hasLeftWidgets = [_leftPanelController hasWidgets];
    BOOL hasBottomWidgets = [_bottomPanelController hasWidgets];
    BOOL hasRightWidgets = [_rightPanelController hasWidgets];
    [self configureLayerWidgets:hasTopWidgets];

    if (_alarmControl && _alarmControl.superview && !_alarmControl.hidden)
    {
        CGRect optionsButtonFrame = _mapHudViewController.optionsMenuButton.frame;
        _alarmControl.center = CGPointMake(_alarmControl.bounds.size.width / 2 + [OAUtilities getLeftMargin], optionsButtonFrame.origin.y - _alarmControl.bounds.size.height / 2);
    }

    if (_rulerControl && _rulerControl.superview && !_rulerControl.hidden)
    {
        CGRect superFrame = _rulerControl.superview.frame;
        _rulerControl.frame = CGRectMake(superFrame.origin.x, superFrame.origin.y, superFrame.size.width, superFrame.size.height);
        _rulerControl.center = _rulerControl.superview.center;
    }

    _mapHudViewController.topWidgetsViewWidthConstraint.constant = [OAUtilities isLandscapeIpadAware] ? kInfoViewLandscapeWidthPad : DeviceScreenWidth;

    if ((hasTopWidgets || hasTopSpecialWidgets) && _lastUpdateTime == 0)
        [[OARootViewController instance].mapPanel updateToolbar];

    if (hasTopWidgets)
    {
        _mapHudViewController.topWidgetsViewHeightConstraint.constant = [_topPanelController calculateContentSize].height;
    }
    else
    {
        _mapHudViewController.topWidgetsViewHeightConstraint.constant = 0.;
    }

    if (hasTopSpecialWidgets)
    {
        _mapHudViewController.middleWidgetsViewYConstraint.constant = kWidgetsTopPadding;
        CGSize specialPanelSize = [_topPanelController.specialPanelController calculateContentSize];
        _mapHudViewController.middleWidgetsViewWidthConstraint.constant = specialPanelSize.width;
        _mapHudViewController.middleWidgetsViewHeightConstraint.constant = specialPanelSize.height;
    }
    else
    {
        _mapHudViewController.middleWidgetsViewHeightConstraint.constant = 0.;
    }

    if (hasLeftWidgets)
    {
        CGSize leftSize = [_leftPanelController calculateContentSize];
        CGFloat pageControlHeight = _leftPanelController.pages.count > 1 ? 16 : 0;
        _mapHudViewController.leftWidgetsViewHeightConstraint.constant = leftSize.height + pageControlHeight;
        _mapHudViewController.leftWidgetsViewWidthConstraint.constant = leftSize.width;
    }
    else
    {
        _mapHudViewController.leftWidgetsViewHeightConstraint.constant = 0.;
        _mapHudViewController.leftWidgetsViewWidthConstraint.constant = 0.;
    }

    _mapHudViewController.bottomWidgetsViewWidthConstraint.constant = [OAUtilities isLandscapeIpadAware] ? kInfoViewLandscapeWidthPad : DeviceScreenWidth;
    _mapHudViewController.bottomWidgetsViewHeightConstraint.constant = hasBottomWidgets ? [_bottomPanelController calculateContentSize].height : 0.;
    
    OAMapRendererView *mapView = [OARootViewController instance].mapPanel.mapViewController.mapView;
    CGFloat topOffset = _mapHudViewController.topWidgetsViewHeightConstraint.constant;
    CGFloat bottomOffset = _mapHudViewController.bottomWidgetsViewHeightConstraint.constant;
    if (topOffset > 0)
        topOffset += _mapHudViewController.statusBarViewHeightConstraint.constant;
    if (bottomOffset > 0)
        bottomOffset += _mapHudViewController.bottomBarViewHeightConstraint.constant;
    [mapView setTopOffsetOfViewSize:topOffset bottomOffset:bottomOffset];

    if (hasRightWidgets)
    {
        CGSize rightSize = [_rightPanelController calculateContentSize];
        CGFloat pageControlHeight = _rightPanelController.pages.count > 1 ? 16 : 0;
        _mapHudViewController.rightWidgetsViewHeightConstraint.constant = rightSize.height + pageControlHeight;
        _mapHudViewController.rightWidgetsViewWidthConstraint.constant = rightSize.width;
    }
    else
    {
        _mapHudViewController.rightWidgetsViewHeightConstraint.constant = 0.;
        _mapHudViewController.rightWidgetsViewWidthConstraint.constant = 0.;
    }
    CGFloat leftRightWidgetsViewTopConstraintConstant = hasTopWidgets ? 1 : 0;
    if ([OAUtilities isLandscapeIpadAware])
    {
        if (hasLeftWidgets)
        {
            leftRightWidgetsViewTopConstraintConstant = _mapHudViewController.topWidgetsViewHeightConstraint.constant > 0 ? -_mapHudViewController.topWidgetsViewHeightConstraint.constant : kWidgetsTopPadding;
        } else
        {
            leftRightWidgetsViewTopConstraintConstant = -_mapHudViewController.topWidgetsViewHeightConstraint.constant + 16;
        }
    }
    
    _mapHudViewController.leftWidgetsViewTopConstraint.constant =
    _mapHudViewController.rightWidgetsViewTopConstraint.constant = leftRightWidgetsViewTopConstraintConstant;

    if (_downloadMapWidget && _downloadMapWidget.superview && !_downloadMapWidget.hidden)
    {
        if (_lastUpdateTime == 0)
            [[OARootViewController instance].mapPanel updateToolbar];
        
        if (portrait)
        {
            _downloadMapWidget.frame = CGRectMake(0, _mapHudViewController.statusBarView.frame.size.height, DeviceScreenWidth, 155.);
        }
        else
        {
            CGFloat widgetWidth = DeviceScreenWidth / 2;
            CGFloat leftOffset = widgetWidth / 2 - [OAUtilities getLeftMargin];
            _downloadMapWidget.frame = CGRectMake(leftOffset, _mapHudViewController.statusBarView.frame.size.height, widgetWidth, 155.);
        }
    }

    if (_weatherToolbar && _weatherToolbar.superview)
        [self updateWeatherToolbarVisible];

    [self.delegate widgetsLayoutDidChange:YES];
}

- (void)updateWeatherToolbarVisible
{
    if (_weatherToolbarVisible && (_weatherToolbar.hidden || _weatherToolbar.frame.origin.y != [OAWeatherToolbar calculateY]))
        [self showWeatherToolbar];
    else if (!_weatherToolbarVisible && !_weatherToolbar.hidden && _weatherToolbar.frame.origin.y != [OAWeatherToolbar calculateYOutScreen])
        [self hideWeatherToolbar];
}

- (void)showWeatherToolbar
{
    OAMapPanelViewController *mapPanel = [OARootViewController instance].mapPanel;
    if (!mapPanel.hudViewController.weatherToolbar.needsSettingsForToolbar)
    {
        mapPanel.mapViewController.mapLayers.weatherDate = [NSDate date];
        [_weatherToolbar resetHandlersData];
    }

    mapPanel.hudViewController.weatherToolbar.needsSettingsForToolbar = NO;
    [mapPanel.weatherToolbarStateChangeObservable notifyEvent];

    if (_weatherToolbar.hidden)
    {
        [_weatherToolbar moveOutOfScreen];
        _weatherToolbar.hidden = NO;
        [_mapHudViewController updateWeatherButtonVisibility];
    }

    _isBordersOfDownloadedMaps = [_settings.mapSettingShowBordersOfDownloadedMaps get];
    if (_isBordersOfDownloadedMaps)
    {
        [_settings.mapSettingShowBordersOfDownloadedMaps set:NO];
        [[[OsmAndApp instance] mapSettingsChangeObservable] notifyEvent];
    }

    [UIView animateWithDuration:.3 animations:^{
        [_weatherToolbar moveToScreen];
        [mapPanel targetUpdateControlsLayout:NO customStatusBarStyle:UIStatusBarStyleDefault];
        [_mapHudViewController.floatingButtonsController updateViewVisibility];
        [self recreateControls];
    }];
}

- (void)hideWeatherToolbar
{
    OAMapPanelViewController *mapPanel = [OARootViewController instance].mapPanel;
    BOOL needsSettingsForToolbar = mapPanel.hudViewController.weatherToolbar.needsSettingsForToolbar;
    if (!needsSettingsForToolbar)
    {
        mapPanel.mapViewController.mapLayers.weatherDate = [NSDate date];
        [mapPanel targetUpdateControlsLayout:NO customStatusBarStyle:UIStatusBarStyleDefault];
    }
    [mapPanel.weatherToolbarStateChangeObservable notifyEvent];

    if (_isBordersOfDownloadedMaps)
    {
        [_settings.mapSettingShowBordersOfDownloadedMaps set:YES];
        [[[OsmAndApp instance] mapSettingsChangeObservable] notifyEvent];
    }

    _weatherToolbar.hidden = YES;
    [_mapHudViewController updateWeatherButtonVisibility];
    [UIView animateWithDuration:.3 animations: ^{
        [_weatherToolbar moveOutOfScreen];
    }                completion:^(BOOL finished) {
        if (needsSettingsForToolbar)
        {
            OAWeatherLayerSettingsViewController *weatherLayerSettingsViewController =
            [[OAWeatherLayerSettingsViewController alloc] initWithLayerType:(EOAWeatherLayerType) _weatherToolbar.selectedLayerIndex];
            weatherLayerSettingsViewController.delegate = self;
            [mapPanel showScrollableHudViewController:weatherLayerSettingsViewController];
        }
    }];
    [_mapHudViewController.floatingButtonsController updateViewVisibility];
    [self recreateControls];
}

- (void) recreateAllControls
{
    [_mapWidgetRegistry clearWidgets];
    [self registerAllControls];
    //[_mapWidgetRegistry reorderWidgets];
    [self recreateControls:NO];
}

- (void) recreateControls
{
    [self recreateControls:YES];
}

- (void) recreateControls:(BOOL)registerWidgets
{
    if (registerWidgets)
        [_mapWidgetRegistry registerAllControls];

    OAApplicationMode *appMode = _settings.applicationMode.get;

    [_mapHudViewController setDownloadMapWidget:_downloadMapWidget];
    [_mapHudViewController setWeatherToolbarMapWidget:_weatherToolbar];

    [_rulerControl removeFromSuperview];
    [[OARootViewController instance].mapPanel.mapViewController.view insertSubview:_rulerControl atIndex:0];
    [self updateRuler];

    [_alarmControl removeFromSuperview];
    _alarmControl.delegate = self;
    [_mapHudViewController.view addSubview:_alarmControl];

    [_mapWidgetRegistry updateWidgetsInfo:[[OAAppSettings sharedManager].applicationMode get]];

    [self recreateWidgetsPanel:_topPanelController panel:OAWidgetsPanel.topPanel appMode:appMode];
    [self recreateWidgetsPanel:_bottomPanelController panel:OAWidgetsPanel.bottomPanel appMode:appMode];
    [self recreateWidgetsPanel:_leftPanelController panel:OAWidgetsPanel.leftPanel appMode:appMode];
    [self recreateWidgetsPanel:_rightPanelController panel:OAWidgetsPanel.rightPanel appMode:appMode];

    _themeId = -1;
    [self updateColorShadowsOfText];
    [self layoutWidgets];
}

- (void)recreateTopWidgetsPanel
{
    OAApplicationMode *appMode = [[OAAppSettings sharedManager].applicationMode get];
    [_mapWidgetRegistry updateWidgetsInfo:appMode];
    [self recreateWidgetsPanel:_topPanelController panel:OAWidgetsPanel.topPanel appMode:appMode];
}

- (void)recreateWidgetsPanel:(OAWidgetPanelViewController *)container panel:(OAWidgetsPanel *)panel appMode:(OAApplicationMode *)appMode
{
    if (container)
    {
        [container clearWidgets];
        [_mapWidgetRegistry populateControlsContainer:container mode:appMode widgetPanel:panel];
        [container updateWidgetSizes];
    }
}

- (void) expandClicked:(id)sender
{
    _expanded = !_expanded;
    [self recreateControls];
}

- (OATextState *) calculateTextState
{
    OARoutingHelper *routingHelper = [OARoutingHelper sharedInstance];

    BOOL transparent = [_settings.transparentMapTheme get];
    BOOL nightMode = _settings.nightMode;
    BOOL following = [routingHelper isFollowingMode];
    OATextState *ts = [[OATextState alloc] init];
    ts.textBold = following;
    ts.night = nightMode;
    ts.textColor = nightMode ? UIColorFromRGB(0xC8C8C8) : [UIColor blackColor];
    
    // Night shadowColor always use widgettext_shadow_night, same as widget background color for non-transparent
    ts.textShadowColor = nightMode ? UIColorFromARGB(color_widgettext_shadow_night_argb) : [UIColor whiteColor];
    if (!transparent && !nightMode)
        ts.textShadowRadius = 0;
    else
        ts.textShadowRadius = 16.0;

    if (transparent)
    {
        //ts.boxTop = R.drawable.btn_flat_transparent;
        ts.rightColor = [UIColor clearColor];
        ts.leftColor = [UIColor clearColor];
        //ts.boxFree = R.drawable.btn_round_transparent;
    }
    else if (nightMode)
    {
        //ts.boxTop = R.drawable.btn_flat_night;
        ts.rightColor = UIColorFromRGBA(0x000000a0);
        ts.leftColor = UIColorFromRGBA(0x000000a0);
        //ts.boxFree = R.drawable.btn_round_night;
    }
    else
    {
        //ts.boxTop = R.drawable.btn_flat;
        ts.rightColor = [UIColor whiteColor];
        ts.leftColor = [UIColor whiteColor];
        //ts.boxFree = R.drawable.btn_round;
    }
    
    return ts;
}

- (void) updateColors:(OATextState *)state sideWidget:(OABaseWidgetView *)sideWidget
{
    if ([sideWidget isKindOfClass:OATextInfoWidget.class])
    {
        OATextInfoWidget *widget = (OATextInfoWidget *) sideWidget;
        widget.backgroundColor = state.leftColor;
        [widget updateTextColor:state.textColor textShadowColor:state.textShadowColor bold:state.textBold shadowRadius:state.textShadowRadius];
        [widget updateIconMode:state.night];
    }
}

- (void) removeSideWidget:(OATextInfoWidget *)widget
{
    [_mapWidgetRegistry removeSideWidgetInternal:widget];
}

- (void) registerAllControls
{
    NSMutableArray<OABaseWidgetView *> *widgetsToUpdate = [NSMutableArray array];

    _alarmControl = [[OAAlarmWidget alloc] init];
    _alarmControl.delegate = self;
    [widgetsToUpdate addObject:_alarmControl];

    _downloadMapWidget = [[OADownloadMapWidget alloc] init];
    _downloadMapWidget.delegate = self;
    [widgetsToUpdate addObject:_downloadMapWidget];

    _weatherToolbar = [[OAWeatherToolbar alloc] init];
    _weatherToolbar.delegate = self;
    [widgetsToUpdate addObject:_weatherToolbar];

    _widgetsToUpdate = widgetsToUpdate;

    if (_rulerControl)
        [_rulerControl removeFromSuperview];

    _rulerControl = [[OARulerWidget alloc] init];

    [_mapWidgetRegistry registerAllControls];
    _themeId = -1;
    [self updateColorShadowsOfText];
}

- (void) onMapZoomChanged:(id)observable withKey:(id)key andValue:(id)value
{
    [self updateRuler];
}

#pragma mark - OAWidgetListener

- (void) widgetChanged:(OABaseWidgetView *)widget
{
    if (widget.isTopText || widget.isTextInfo)
        [self layoutWidgets];
}

- (void) widgetVisibilityChanged:(OABaseWidgetView *)widget visible:(BOOL)visible
{
    [self layoutWidgets];
}

- (void) widgetClicked:(OABaseWidgetView *)widget
{
    if (!widget.isTopText)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [_mapWidgetRegistry updateInfo:_settings.applicationMode.get expanded:_expanded];
        });
    }
}

#pragma mark - OAWeatherLayerSettingsDelegate

- (void)onDoneWeatherLayerSettings:(BOOL)show
{
    if (show)
        [_mapHudViewController changeWeatherToolbarVisible];
}

// MARK: OAWidgetPanelDelegate

- (void)onPanelSizeChanged
{
    [self layoutWidgets];
}

@end
