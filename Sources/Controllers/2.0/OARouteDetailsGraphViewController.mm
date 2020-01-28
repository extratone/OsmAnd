//
//  OARouteDetailsGraphViewController.m
//  OsmAnd
//
//  Created by Paul on 17/12/2019.
//  Copyright © 2019 OsmAnd. All rights reserved.
//

#import "OARouteDetailsGraphViewController.h"
#import "Localization.h"
#import "OARootViewController.h"
#import "OASizes.h"
#import "OAColors.h"
#import "OAStateChangedListener.h"
#import "OARoutingHelper.h"
#import "OAGPXTrackAnalysis.h"
#import "OANativeUtilities.h"
#import "OALineChartCell.h"
#import "OARouteInfoCell.h"
#import "OsmAndApp.h"
#import "OAGPXDocument.h"
#import "OAGPXUIHelper.h"
#import "OAMapLayers.h"
#import "OARouteLayer.h"
#import "OARouteStatisticsHelper.h"
#import "OARouteCalculationResult.h"
#import "OsmAnd_Maps-Swift.h"
#import "Localization.h"
#import "OARouteStatistics.h"
#import "OARouteInfoAltitudeCell.h"
#import "OATargetPointsHelper.h"
#import "OAMapRendererView.h"
#import "OARouteInfoLegendItemView.h"
#import "OARouteInfoLegendCell.h"
#import "OARouteStatisticsModeCell.h"
#import "OAStatisticsSelectionBottomSheetViewController.h"

#import <Charts/Charts-Swift.h>

#include <OsmAndCore/Utilities.h>

@interface OARouteDetailsGraphViewController () <OAStateChangedListener, ChartViewDelegate, OAStatisticsSelectionDelegate>

@end

@implementation OARouteDetailsGraphViewController
{
    NSArray *_data;
    
    EOARouteStatisticsMode _currentMode;
    
    BOOL _hasTranslated;
    double _highlightDrawX;
    
    CGPoint _lastTranslation;
    
    CGFloat _cachedYViewPort;
    OAMapRendererView *_mapView;
}

- (NSArray *) getMainGraphSectionData
{
    NSArray *nib = [[NSBundle mainBundle] loadNibNamed:@"OALineChartCell" owner:self options:nil];
    OALineChartCell *routeStatsCell = (OALineChartCell *)[nib objectAtIndex:0];
    routeStatsCell.selectionStyle = UITableViewCellSelectionStyleNone;
    routeStatsCell.lineChartView.delegate = self;
    [GpxUIHelper refreshLineChartWithChartView:routeStatsCell.lineChartView analysis:self.analysis useGesturesAndScale:YES];
    
    BOOL hasSlope = routeStatsCell.lineChartView.lineData.dataSetCount > 1;
    
    self.statisticsChart = routeStatsCell.lineChartView;
    for (UIGestureRecognizer *recognizer in self.statisticsChart.gestureRecognizers)
    {
        if ([recognizer isKindOfClass:UIPanGestureRecognizer.class])
        {
            [recognizer addTarget:self action:@selector(onBarChartScrolled:)];
        }
        [recognizer addTarget:self action:@selector(onChartGesture:)];
    }
    
    if (hasSlope)
    {
        nib = [[NSBundle mainBundle] loadNibNamed:@"OARouteStatisticsModeCell" owner:self options:nil];
        OARouteStatisticsModeCell *modeCell = (OARouteStatisticsModeCell *)[nib objectAtIndex:0];
        modeCell.selectionStyle = UITableViewCellSelectionStyleNone;
        [modeCell.modeButton setTitle:[NSString stringWithFormat:@"%@/%@", OALocalizedString(@"map_widget_altitude"), OALocalizedString(@"gpx_slope")] forState:UIControlStateNormal];
        [modeCell.modeButton addTarget:self action:@selector(onStatsModeButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        [modeCell.iconButton addTarget:self action:@selector(onStatsModeButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
        modeCell.rightLabel.text = OALocalizedString(@"shared_string_distance");
        modeCell.separatorInset = UIEdgeInsetsMake(0., CGFLOAT_MAX, 0., 0.);
        
        return @[modeCell, routeStatsCell];
    }
    else
    {
        return @[routeStatsCell];
    }
}

- (void) generateData
{
    self.gpx = [OAGPXUIHelper makeGpxFromRoute:self.routingHelper.getRoute];
    self.analysis = [self.gpx getAnalysis:0];
    _currentMode = EOARouteStatisticsModeBoth;
    _lastTranslation = CGPointZero;
    _mapView = [OARootViewController instance].mapPanel.mapViewController.mapView;
    _cachedYViewPort = _mapView.viewportYScale;
    
    _data = [self getMainGraphSectionData];
}

- (BOOL)hasControlButtons
{
    return NO;
}

- (NSAttributedString *)getAttributedTypeStr
{
    return nil;
}

- (NSAttributedString *) getAdditionalInfoStr
{
    return nil;
}

- (NSString *)getTypeStr
{
    return nil;
}

- (BOOL) isLandscape
{
    return OAUtilities.isLandscape && !OAUtilities.isIPad;
}

- (CGFloat) additionalContentOffset
{
    return OAUtilities.isLandscape ? 0.0 : 200. + OAUtilities.getBottomMargin;
}

- (BOOL)hasInfoView
{
    return NO;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self setupRouteInfo];
    
    [self generateData];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = UIColor.whiteColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [_tableView setScrollEnabled:NO];
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 125.;
}

- (void) setupRouteInfo
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.delegate)
            [self.delegate contentChanged];
    });
}

- (NSAttributedString *) formatDistance:(NSString *)dist numericAttributes:(NSDictionary *) numericAttributes alphabeticAttributes:(NSDictionary *)alphabeticAttributes
{
    NSMutableAttributedString *res = [[NSMutableAttributedString alloc] init];
    if (dist.length > 0)
    {
        NSArray<NSString *> *components = [[dist trim] componentsSeparatedByString:@" "];
        NSAttributedString *space = [[NSAttributedString alloc] initWithString:@" "];
        for (NSInteger i = 0; i < components.count; i++)
        {
            NSAttributedString *str = [[NSAttributedString alloc] initWithString:components[i] attributes:i % 2 == 0 ? numericAttributes : alphabeticAttributes];
            [res appendAttributedString:str];
            if (i != components.count - 1)
                [res appendAttributedString:space];
        }
    }
    return res;
}

- (void)refreshContent
{
    [self generateData];
    [self.tableView reloadData];
}

- (UIView *) getTopView
{
    return self.navBar;
}

- (UIView *) getMiddleView
{
    return self.contentView;
}


- (CGFloat)getNavBarHeight
{
    return defaultNavBarHeight;
}

- (BOOL) hasTopToolbar
{
    return YES;
}

- (BOOL) needsLayoutOnModeChange
{
    return NO;
}

- (BOOL) shouldShowToolbar
{
    return YES;
}

- (BOOL)supportMapInteraction
{
    return YES;
}

- (BOOL)supportFullScreen
{
    return NO;
}

- (BOOL)supportFullMenu
{
    return NO;
}

- (ETopToolbarType) topToolbarType
{
    return ETopToolbarTypeFixed;
}

- (void)onMenuDismissed
{
    [[OARootViewController instance].mapPanel.mapViewController.mapLayers.routeMapLayer hideCurrentStatisticsLocation];
}

- (void) applyLocalization
{
    self.titleView.text = OALocalizedString(@"gpx_analyze");
}

- (CGFloat)contentHeight
{
    return _tableView.contentSize.height;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        _tableView.contentInset = UIEdgeInsetsMake(0., 0., [self getToolBarHeight], 0.);
        if (self.delegate)
            [self.delegate contentChanged];
    } completion:nil];
}

- (void) onStatsModeButtonPressed:(id)sender
{
    OAStatisticsSelectionBottomSheetViewController *statsModeBottomSheet = [[OAStatisticsSelectionBottomSheetViewController alloc] initWithMode:_currentMode];
    statsModeBottomSheet.delegate = self;
    [statsModeBottomSheet show];
}

- (void) onChartGesture:(UIGestureRecognizer *)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateBegan)
    {
        _hasTranslated = NO;
        if (self.statisticsChart.highlighted.count > 0)
            _highlightDrawX = self.statisticsChart.highlighted.firstObject.drawX;
        else
            _highlightDrawX = -1;
    }
    else if (([recognizer isKindOfClass:UIPinchGestureRecognizer.class] ||
              ([recognizer isKindOfClass:UITapGestureRecognizer.class] && (((UITapGestureRecognizer *) recognizer).nsuiNumberOfTapsRequired == 2)))
             && recognizer.state == UIGestureRecognizerStateEnded)
    {
        [self refreshHighlightOnMap:YES];
    }
}

- (void) onBarChartScrolled:(UIPanGestureRecognizer *)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateChanged)
    {
        if (self.statisticsChart.lowestVisibleX > 0.1 && self.statisticsChart.highestVisibleX != self.statisticsChart.chartXMax)
        {
            _lastTranslation = [recognizer translationInView:self.statisticsChart];
            return;
        }
        
        ChartHighlight *lastHighlighted = self.statisticsChart.lastHighlighted;
        CGPoint touchPoint = [recognizer locationInView:self.statisticsChart];
        CGPoint translation = [recognizer translationInView:self.statisticsChart];
        ChartHighlight *h = [self.statisticsChart getHighlightByTouchPoint:CGPointMake(self.statisticsChart.isFullyZoomedOut ? touchPoint.x : _highlightDrawX + (_lastTranslation.x - translation.x), 0.)];
        
        if (h != lastHighlighted)
        {
            self.statisticsChart.lastHighlighted = h;
            [self.statisticsChart highlightValue:h callDelegate:YES];
        }
    }
    else if (recognizer.state == UIGestureRecognizerStateEnded)
    {
        _lastTranslation = CGPointZero;
        if (self.statisticsChart.highlighted.count > 0)
            _highlightDrawX = self.statisticsChart.highlighted.firstObject.drawX;
    }
}

- (IBAction)buttonDonePressed:(id)sender
{
    [self cancelPressed];
}

- (void) cancelPressed
{
    [[OARootViewController instance].mapPanel openTargetViewWithRouteDetails];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _data.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 0.001;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return _data[indexPath.row];
}


#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - OAStateChangedListener

- (void) stateChanged:(id)change
{
    [self refreshContent];
}

#pragma - mark ChartViewDelegate

- (void)chartValueNothingSelected:(ChartViewBase *)chartView
{
    [[OARootViewController instance].mapPanel.mapViewController.mapLayers.routeMapLayer hideCurrentStatisticsLocation];
}

- (void)chartValueSelected:(ChartViewBase *)chartView entry:(ChartDataEntry *)entry highlight:(ChartHighlight *)highlight
{
    [self refreshHighlightOnMap:NO];
}


#pragma mark - OAStatisticsSelectionDelegate

- (void)onNewModeSelected:(EOARouteStatisticsMode)mode
{
    _currentMode = mode;
    [self updateRouteStatisticsGraph];
}

- (void) updateRouteStatisticsGraph
{
    if (_data.count > 1)
    {
        OARouteStatisticsModeCell *statsModeCell = _data[0];
        OALineChartCell *graphCell = _data[1];
        
        switch (_currentMode) {
            case EOARouteStatisticsModeBoth:
            {
                [statsModeCell.modeButton setTitle:[NSString stringWithFormat:@"%@/%@", OALocalizedString(@"map_widget_altitude"), OALocalizedString(@"gpx_slope")] forState:UIControlStateNormal];
                for (id<IChartDataSet> data in graphCell.lineChartView.lineData.dataSets)
                {
                    data.visible = YES;
                }
                graphCell.lineChartView.leftAxis.enabled = YES;
                graphCell.lineChartView.leftAxis.drawLabelsEnabled = NO;
                graphCell.lineChartView.rightAxis.enabled = YES;
                ChartYAxisCombinedRenderer *renderer = (ChartYAxisCombinedRenderer *) graphCell.lineChartView.rightYAxisRenderer;
                renderer.renderingMode = YAxisCombinedRenderingModeBothValues;
                break;
            }
            case EOARouteStatisticsModeAltitude:
            {
                [statsModeCell.modeButton setTitle:OALocalizedString(@"map_widget_altitude") forState:UIControlStateNormal];
                graphCell.lineChartView.lineData.dataSets[0].visible = YES;
                graphCell.lineChartView.lineData.dataSets[1].visible = NO;
                graphCell.lineChartView.leftAxis.enabled = YES;
                graphCell.lineChartView.leftAxis.drawLabelsEnabled = YES;
                graphCell.lineChartView.rightAxis.enabled = NO;
                break;
            }
            case EOARouteStatisticsModeSlope:
            {
                [statsModeCell.modeButton setTitle:OALocalizedString(@"gpx_slope") forState:UIControlStateNormal];
                graphCell.lineChartView.lineData.dataSets[0].visible = NO;
                graphCell.lineChartView.lineData.dataSets[1].visible = YES;
                graphCell.lineChartView.leftAxis.enabled = NO;
                graphCell.lineChartView.leftAxis.drawLabelsEnabled = NO;
                graphCell.lineChartView.rightAxis.enabled = YES;
                ChartYAxisCombinedRenderer *renderer = (ChartYAxisCombinedRenderer *) graphCell.lineChartView.rightYAxisRenderer;
                renderer.renderingMode = YAxisCombinedRenderingModePrimaryValueOnly;
                break;
            }
            default:
                break;
        }
        [graphCell.lineChartView notifyDataSetChanged];
    }
}


@end
