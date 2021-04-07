//
//  OADestinationsLayer.m
//  OsmAnd
//
//  Created by Alexey Kulish on 09/06/2017.
//  Copyright © 2017 OsmAnd. All rights reserved.
//

#import "OADestinationsLayer.h"
#import "OANativeUtilities.h"
#import "OAMapViewController.h"
#import "OAMapRendererView.h"
#import "OAUtilities.h"
#import "OADestination.h"
#import "OAAutoObserverProxy.h"
#import "OATargetPointsHelper.h"
#import "OARTargetPoint.h"
#import "OAStateChangedListener.h"
#import "OATargetPoint.h"
#import "OADestinationsHelper.h"
#import "OADestinationsLineWidget.h"
#import "OARootViewController.h"
#import "OAMapInfoController.h"
#import "OAMapHudViewController.h"
#import "OAReverseGeocoder.h"
#import "OAPointDescription.h"
#import "OAAppSettings.h"
#import "OAMapLayers.h"

#include <OsmAndCore/Utilities.h>
#include <OsmAndCore/Map/MapMarker.h>
#include <OsmAndCore/Map/MapMarkerBuilder.h>
#include <OsmAndCore/Map/VectorLinesCollection.h>
#include <OsmAndCore/Map/VectorLine.h>
#include <OsmAndCore/Map/VectorLineBuilder.h>

@interface OADestinationsLayer () <OAStateChangedListener>

@end

@implementation OADestinationsLayer
{
    std::shared_ptr<OsmAnd::MapMarkersCollection> _destinationsMarkersCollection;
    std::shared_ptr<OsmAnd::VectorLinesCollection> _linesCollection;

    OAAutoObserverProxy* _destinationAddObserver;
    OAAutoObserverProxy* _destinationRemoveObserver;
    OAAutoObserverProxy* _destinationShowObserver;
    OAAutoObserverProxy* _destinationHideObserver;
    OAAutoObserverProxy* _locationServicesUpdateObserver;
    
    OATargetPointsHelper *_targetPoints;
    OADestinationsLineWidget *_destinationLayerWidget;

    BOOL _showCaptionsCache;
    double _textSize;
    int _myPositionLayerBaseOrder;
}

- (NSString *) layerId
{
    return kDestinationsLayerId;
}

- (void) initLayer
{
    [super initLayer];
    
    _showCaptionsCache = self.showCaptions;
    _textSize = OAAppSettings.sharedManager.textSize.get;

    _destinationAddObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                           withHandler:@selector(onDestinationAdded:withKey:)
                                                            andObserve:self.app.data.destinationAddObservable];

    _destinationRemoveObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                           withHandler:@selector(onDestinationRemoved:withKey:)
                                                            andObserve:self.app.data.destinationRemoveObservable];

    _destinationShowObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                         withHandler:@selector(onDestinationShow:withKey:)
                                                          andObserve:self.app.data.destinationShowObservable];
    _destinationHideObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                         withHandler:@selector(onDestinationHide:withKey:)
                                                          andObserve:self.app.data.destinationHideObservable];
    
    _locationServicesUpdateObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                                withHandler:@selector(onLocationServicesUpdate)
                                                                 andObserve:self.app.locationServices.updateObserver];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onProfileSettingSet:) name:kNotificationSetProfileSetting object:nil];

    _linesCollection = std::make_shared<OsmAnd::VectorLinesCollection>();
    _myPositionLayerBaseOrder = self.mapViewController.mapLayers.myPositionLayer.baseOrder;
    
    [self refreshDestinationsMarkersCollection];
    
    [self.app.data.mapLayersConfiguration setLayer:self.layerId Visibility:YES];
    
    _targetPoints = [OATargetPointsHelper sharedInstance];
    [_targetPoints addListener:self];

    _destinationLayerWidget = [[OADestinationsLineWidget alloc] init];
    [self.mapView addSubview:_destinationLayerWidget];
}

- (void) onMapFrameRendered
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [_destinationLayerWidget updateLayer];
    });
}

- (void) deinitLayer
{
    [super deinitLayer];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
     
    [_targetPoints removeListener:self];

    if (_destinationShowObserver)
    {
        [_destinationShowObserver detach];
        _destinationShowObserver = nil;
    }
    if (_destinationHideObserver)
    {
        [_destinationHideObserver detach];
        _destinationHideObserver = nil;
    }
    if (_destinationAddObserver)
    {
        [_destinationAddObserver detach];
        _destinationAddObserver = nil;
    }
    if (_destinationRemoveObserver)
    {
        [_destinationRemoveObserver detach];
        _destinationRemoveObserver = nil;
    }
    if (_locationServicesUpdateObserver)
    {
        [_locationServicesUpdateObserver detach];
        _locationServicesUpdateObserver = nil;
    }
}

- (void) onProfileSettingSet:(NSNotification *)notification
{
    OAProfileSetting *obj = notification.object;
    OAAppSettings *settings = [OAAppSettings sharedManager];
    OAProfileActiveMarkerConstant *activeMarkers = settings.activeMarkers;
    OAProfileBoolean *directionLines = settings.directionLines;
    if (obj)
    {
        if (obj == activeMarkers || obj == directionLines)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self drawDestinationLines];
            });
        }
    }
}

- (BOOL) updateLayer
{
    [super updateLayer];
    
    if (self.showCaptions != _showCaptionsCache || _textSize != OAAppSettings.sharedManager.textSize.get)
    {
        _showCaptionsCache = self.showCaptions;
        _textSize = OAAppSettings.sharedManager.textSize.get;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self hide];
            [self refreshDestinationsMarkersCollection];
            [self show];
        });
    }
    
    return YES;
}

- (std::shared_ptr<OsmAnd::MapMarkersCollection>) getDestinationsMarkersCollection
{
    return _destinationsMarkersCollection;
}

- (void) refreshDestinationsMarkersCollection
{
    _destinationsMarkersCollection.reset(new OsmAnd::MapMarkersCollection());

    for (OADestination *destination in self.app.data.destinations)
    {
        if (!destination.routePoint && !destination.hidden)
        {
            [self addDestinationPin:destination.markerResourceName color:destination.color latitude:destination.latitude longitude:destination.longitude description:destination.desc];
            [_destinationLayerWidget drawLineArrowWidget:destination];
        }
    }

    [self drawDestinationLines];
}

- (void) addDestinationPin:(NSString *)markerResourceName color:(UIColor *)color latitude:(double)latitude longitude:(double)longitude description:(NSString *)description
{
    CGFloat r,g,b,a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    OsmAnd::FColorRGB col(r, g, b);
    
    const OsmAnd::LatLon latLon(latitude, longitude);
    
    OsmAnd::MapMarkerBuilder builder;
    builder.setIsAccuracyCircleSupported(false)
    .setBaseOrder(self.baseOrder)
    .setIsHidden(false)
    .setPinIcon([OANativeUtilities skBitmapFromPngResource:markerResourceName])
    .setPosition(OsmAnd::Utilities::convertLatLonTo31(latLon))
    .setPinIconVerticalAlignment(OsmAnd::MapMarker::Top)
    .setPinIconHorisontalAlignment(OsmAnd::MapMarker::CenterHorizontal)
    .setAccuracyCircleBaseColor(col);
    
    if (self.showCaptions && description.length > 0)
    {
        builder.setCaption(QString::fromNSString(description));
        builder.setCaptionStyle(self.captionStyle);
        builder.setCaptionTopSpace(self.captionTopSpace);
    }
    
    builder.buildAndAddToCollection(_destinationsMarkersCollection);
}

- (void) removeDestinationPin:(double)latitude longitude:(double)longitude;
{
    for (const auto &marker : _destinationsMarkersCollection->getMarkers())
    {
        OsmAnd::LatLon latLon = OsmAnd::Utilities::convert31ToLatLon(marker->getPosition());
        if ([OAUtilities doublesEqualUpToDigits:5 source:latLon.latitude destination:latitude] &&
            [OAUtilities doublesEqualUpToDigits:5 source:latLon.longitude destination:longitude])
        {
            _destinationsMarkersCollection->removeMarker(marker);
            break;
        }
    }
}

- (void) show
{
    [self.mapViewController runWithRenderSync:^{
        [self.mapView addKeyedSymbolsProvider:_destinationsMarkersCollection];
        [self.mapView addKeyedSymbolsProvider:_linesCollection];
    }];
}

- (void) hide
{
    [self.mapViewController runWithRenderSync:^{
        [self.mapView removeKeyedSymbolsProvider:_destinationsMarkersCollection];
        [self.mapView removeKeyedSymbolsProvider:_linesCollection];
    }];
}

- (void) onDestinationAdded:(id)observable withKey:(id)key
{
    OADestination *destination = key;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addDestinationPin:destination.markerResourceName color:destination.color latitude:destination.latitude longitude:destination.longitude description:destination.desc];
        [_destinationLayerWidget drawLineArrowWidget:destination];
        [self drawDestinationLines];
    });
}

- (void) onDestinationRemoved:(id)observable withKey:(id)key
{
    OADestination *destination = key;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self removeDestinationPin:destination.latitude longitude:destination.longitude];
        [_destinationLayerWidget removeLineToDestinationPin:destination];
        [self drawDestinationLines];
    });
}


- (void) onDestinationShow:(id)observer withKey:(id)key
{
    OADestination *destination = key;
    
    if (destination)
    {
        BOOL exists = NO;
        for (const auto &marker : _destinationsMarkersCollection->getMarkers())
        {
            OsmAnd::LatLon latLon = OsmAnd::Utilities::convert31ToLatLon(marker->getPosition());
            if ([OAUtilities doublesEqualUpToDigits:5 source:latLon.latitude destination:destination.latitude] &&
                [OAUtilities doublesEqualUpToDigits:5 source:latLon.longitude destination:destination.longitude])
            {
                exists = YES;
                break;
            }
        }
        
        if (!exists)
        {
            [self addDestinationPin:destination.markerResourceName color:destination.color latitude:destination.latitude longitude:destination.longitude description:destination.desc];
            [_destinationLayerWidget drawLineArrowWidget:destination];
        }
        [self drawDestinationLines];
    }
}

- (void) onDestinationHide:(id)observer withKey:(id)key
{
    OADestination *destination = key;
    
    if (destination)
    {
        for (const auto &marker : _destinationsMarkersCollection->getMarkers())
        {
            OsmAnd::LatLon latLon = OsmAnd::Utilities::convert31ToLatLon(marker->getPosition());
            if ([OAUtilities doublesEqualUpToDigits:5 source:latLon.latitude destination:destination.latitude] &&
                [OAUtilities doublesEqualUpToDigits:5 source:latLon.longitude destination:destination.longitude])
            {
                _destinationsMarkersCollection->removeMarker(marker);
                break;
            }
        }
        [self drawDestinationLines];
    }
}

- (void) drawDestinationLines
{
    [self.mapView removeKeyedSymbolsProvider:_linesCollection];
    _linesCollection = std::make_shared<OsmAnd::VectorLinesCollection>();
    
    if ([OADestinationsHelper instance].sortedDestinations.count > 0)
    {
        OAAppSettings *settings = OAAppSettings.sharedManager;
        NSArray *destinations = [OADestinationsHelper instance].sortedDestinations;
        OADestination *firstMarkerDestination = (destinations.count > 0 ? destinations[0] : nil);
        OADestination *secondMarkerDestination = (destinations.count > 1 ? destinations[1] : nil);
        
        if ([settings.directionLines get])
        {
            CLLocation *currLoc = [self.app.locationServices lastKnownLocation];
            if (currLoc)
            {
                if (firstMarkerDestination)
                    [self drawLine:firstMarkerDestination fromLocation:currLoc lineId:1];
                    
                if (secondMarkerDestination && [settings.activeMarkers get] == TWO_ACTIVE_MARKERS)
                    [self drawLine:secondMarkerDestination fromLocation:currLoc lineId:2];
                else
                    _linesCollection->removeLine([self getLine:2]);
            }
            [self.mapView addKeyedSymbolsProvider:_linesCollection];
        }
    }
}

- (void) drawLine:(OADestination *)destination fromLocation:(CLLocation *)currLoc lineId:(int)lineId
{
    QVector<OsmAnd::PointI> points;
    points.push_back(OsmAnd::Utilities::convertLatLonTo31(OsmAnd::LatLon(destination.latitude, destination.longitude)));
    points.push_back(OsmAnd::Utilities::convertLatLonTo31(OsmAnd::LatLon(currLoc.coordinate.latitude, currLoc.coordinate.longitude)));
    const auto color = [self argbFromUIColor:destination.color];
    const auto& line = [self getLine:lineId];
    if (line == nullptr)
    {
        std::vector<double> linePattern;
        linePattern.push_back(80);
        linePattern.push_back(40);
        OsmAnd::VectorLineBuilder builder;
        builder.setBaseOrder(_myPositionLayerBaseOrder + 10)
        .setIsHidden(false)
        .setLineId(lineId)
        .setLineWidth(16)
        .setLineDash(linePattern)
        .setPoints(points)
        .setFillColor(color);
        
        builder.buildAndAddToCollection(_linesCollection);
    }
    else
    {
        line->setPoints(points);
        line->setFillColor(color);
    }
}

- (const std::shared_ptr<OsmAnd::VectorLine>) getLine:(int)lineId
{
    const auto& lines = _linesCollection->getLines();
    for (auto it = lines.begin(); it != lines.end(); ++it)
    {
        if ((*it)->lineId == lineId)
            return *it;
    }
    return nullptr;
}

- (OsmAnd::FColorARGB) argbFromUIColor:(UIColor *)color
{
    CGFloat red, green, blue, alpha;
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    return OsmAnd::ColorARGB(alpha * 255, red * 255, green * 255, blue * 255);
}

#pragma mark - OAStateChangedListener

- (void) stateChanged:(id)change
{
    if (![change boolValue])
        return;
    
    [self.mapViewController runWithRenderSync:^{

        auto markers = _destinationsMarkersCollection->getMarkers();
        NSArray<OARTargetPoint *> *targets = [_targetPoints getAllPoints];
        for (auto marker : markers)
        {
            auto latLon = OsmAnd::Utilities::convert31ToLatLon(marker->getPosition());
            bool hide = false;
            for (OARTargetPoint *target in targets)
            {
                if ([OAUtilities isCoordEqual:latLon.latitude srcLon:latLon.longitude destLat:target.point.coordinate.latitude destLon:target.point.coordinate.longitude])
                {
                    hide = true;
                    break;
                }
            }
            if (hide && !marker->isHidden())
                marker->setIsHidden(true);
            if (!hide && marker->isHidden())
                marker->setIsHidden(false);
        }
        [self drawDestinationLines];
    }];
}

#pragma mark - OAContextMenuProvider

- (OATargetPoint *) getTargetPoint:(id)obj
{
    if ([obj isKindOfClass:[OADestination class]])
    {
        OADestination *destination = (OADestination *)obj;
        
        OATargetPoint *targetPoint = [[OATargetPoint alloc] init];
        targetPoint.location = CLLocationCoordinate2DMake(destination.latitude, destination.longitude);
        targetPoint.title = destination.desc;
        
        if (destination.parking)
        {
            targetPoint.icon = [UIImage imageNamed:@"map_parking_pin"];
            targetPoint.type = OATargetParking;
        }
        else
        {
            targetPoint.icon = [UIImage imageNamed:destination.markerResourceName];
            targetPoint.type = OATargetDestination;
        }
        
        targetPoint.targetObj = destination;
        
        targetPoint.sortIndex = (NSInteger)targetPoint.type;
        return targetPoint;
    }
    return nil;
}

- (OATargetPoint *) getTargetPointCpp:(const void *)obj
{
    return nil;
}

- (void) collectObjectsFromPoint:(CLLocationCoordinate2D)point touchPoint:(CGPoint)touchPoint symbolInfo:(const OsmAnd::IMapRenderer::MapSymbolInformation *)symbolInfo found:(NSMutableArray<OATargetPoint *> *)found unknownLocation:(BOOL)unknownLocation
{
    if (const auto markerGroup = dynamic_cast<OsmAnd::MapMarker::SymbolsGroup*>(symbolInfo->mapSymbol->groupPtr))
    {
        for (const auto& dest : _destinationsMarkersCollection->getMarkers())
        {
            if (markerGroup->getMapMarker() == dest.get())
            {
                double lat = OsmAnd::Utilities::get31LatitudeY(dest->getPosition().y);
                double lon = OsmAnd::Utilities::get31LongitudeX(dest->getPosition().x);
                
                for (OADestination *destination in self.app.data.destinations)
                {
                    if ([OAUtilities isCoordEqual:destination.latitude srcLon:destination.longitude destLat:lat destLon:lon] && !destination.routePoint)
                    {
                        OATargetPoint *targetPoint = [self getTargetPoint:destination];                        
                        if (![found containsObject:targetPoint])
                            [found addObject:targetPoint];
                    }
                }
            }
        }
    }
}

#pragma mark - OAMoveObjectProvider

- (BOOL)isObjectMovable:(id)object
{
    return [object isKindOfClass:OADestination.class];
}

- (void)applyNewObjectPosition:(id)object position:(CLLocationCoordinate2D)position
{
    if (object && [self isObjectMovable:object])
    {
        OADestination *dest = (OADestination *)object;
        OADestination *destCopy = [dest copy];
        OADestinationsHelper *helper = [OADestinationsHelper instance];
        destCopy.latitude = position.latitude;
        destCopy.longitude = position.longitude;
        NSString *address = [[OAReverseGeocoder instance] lookupAddressAtLat:destCopy.latitude lon:destCopy.longitude];
        address = address && address.length > 0 ? address : [OAPointDescription getLocationNamePlain:destCopy.latitude lon:destCopy.longitude];
        destCopy.desc = address;
        [helper replaceDestination:dest withDestination:destCopy];
        [_destinationLayerWidget moveMarker:-1];
        [self drawDestinationLines];
    }
}

- (UIImage *)getPointIcon:(id)object
{
    if (object && [self isObjectMovable:object])
    {
        OADestination *item = (OADestination *)object;
        return [UIImage imageNamed:item.markerResourceName];
    }
    return nil;
}

- (void)setPointVisibility:(id)object hidden:(BOOL)hidden
{
    if (object && [self isObjectMovable:object])
    {
        OADestination *item = (OADestination *)object;
        const auto& pos = OsmAnd::Utilities::convertLatLonTo31(OsmAnd::LatLon(item.latitude, item.longitude));
        for (const auto& marker : _destinationsMarkersCollection->getMarkers())
        {
            if (pos == marker->getPosition())
            {
                marker->setIsHidden(hidden);
                [_destinationLayerWidget moveMarker:item.index];
            }
        }
    }
}

- (EOAPinVerticalAlignment) getPointIconVerticalAlignment
{
    return EOAPinAlignmentTop;
}


- (EOAPinHorizontalAlignment) getPointIconHorizontalAlignment
{
    return EOAPinAlignmentCenterHorizontal;
}

#pragma mark - LocationServicesUpdate

- (void) onLocationServicesUpdate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self drawDestinationLines];
    });
}

@end
