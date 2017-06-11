//
//  OAOverlayMapLayer.m
//  OsmAnd
//
//  Created by Alexey Kulish on 11/06/2017.
//  Copyright © 2017 OsmAnd. All rights reserved.
//

#import "OAOverlayMapLayer.h"
#import "OAMapCreatorHelper.h"
#import "OAMapViewController.h"
#import "OAMapRendererView.h"
#import "OAAutoObserverProxy.h"

#include "OASQLiteTileSourceMapLayerProvider.h"
#include "OAWebClient.h"
#include <OsmAndCore/IWebClient.h>
#include <OsmAndCore/Map/OnlineTileSources.h>
#include <OsmAndCore/Map/OnlineRasterMapLayerProvider.h>

@implementation OAOverlayMapLayer
{
    std::shared_ptr<OsmAnd::IMapLayerProvider> _rasterOverlayMapProvider;
    OAAutoObserverProxy* _overlayMapSourceChangeObserver;
    OAAutoObserverProxy* _overlayAlphaChangeObserver;
    std::shared_ptr<OsmAnd::IWebClient> _webClient;
}

+ (NSString *) getLayerId
{
    return kOverlayMapLayerId;
}

- (void) initLayer
{
    _webClient = std::make_shared<OAWebClient>();

    _overlayMapSourceChangeObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                                withHandler:@selector(onOverlayLayerChanged)
                                                                 andObserve:self.app.data.overlayMapSourceChangeObservable];
    _overlayAlphaChangeObserver = [[OAAutoObserverProxy alloc] initWith:self
                                                            withHandler:@selector(onOverlayLayerAlphaChanged)
                                                             andObserve:self.app.data.overlayAlphaChangeObservable];
}

- (void) deinitLayer
{
    if (_overlayMapSourceChangeObserver)
    {
        [_overlayMapSourceChangeObserver detach];
        _overlayMapSourceChangeObserver = nil;
    }
    if (_overlayAlphaChangeObserver)
    {
        [_overlayAlphaChangeObserver detach];
        _overlayAlphaChangeObserver = nil;
    }
    
    _webClient = nil;
}

- (void) resetLayer
{
    _rasterOverlayMapProvider.reset();
    [self.mapView resetProviderFor:self.layerIndex];
}

- (BOOL) updateLayer
{
    if (self.app.data.overlayMapSource)
    {
        if ([self.app.data.overlayMapSource.name isEqualToString:@"sqlitedb"])
        {
            NSString *path = [[OAMapCreatorHelper sharedInstance].filesDir stringByAppendingPathComponent:self.app.data.overlayMapSource.resourceId];
            
            const auto sqliteTileSourceMapProvider = std::make_shared<OASQLiteTileSourceMapLayerProvider>(QString::fromNSString(path));
            
            _rasterOverlayMapProvider = sqliteTileSourceMapProvider;
            [self.mapView setProvider:_rasterOverlayMapProvider forLayer:self.layerIndex];
            
            OsmAnd::MapLayerConfiguration config;
            config.setOpacityFactor(self.app.data.overlayAlpha);
            [self.mapView setMapLayerConfiguration:self.layerIndex configuration:config forcedUpdate:NO];
        }
        else
        {
            const auto resourceId = QString::fromNSString(self.app.data.overlayMapSource.resourceId);
            const auto mapSourceResource = self.app.resourcesManager->getResource(resourceId);
            if (mapSourceResource && _webClient)
            {
                const auto& onlineTileSources = std::static_pointer_cast<const OsmAnd::ResourcesManager::OnlineTileSourcesMetadata>(mapSourceResource->metadata)->sources;
                
                const auto onlineMapTileProvider = onlineTileSources->createProviderFor(QString::fromNSString(self.app.data.overlayMapSource.variant), _webClient);
                if (onlineMapTileProvider)
                {
                    onlineMapTileProvider->setLocalCachePath(QString::fromNSString(self.app.cachePath));
                    _rasterOverlayMapProvider = onlineMapTileProvider;
                    [self.mapView setProvider:_rasterOverlayMapProvider forLayer:self.layerIndex];
                    
                    OsmAnd::MapLayerConfiguration config;
                    config.setOpacityFactor(self.app.data.overlayAlpha);
                    [self.mapView setMapLayerConfiguration:self.layerIndex configuration:config forcedUpdate:NO];
                }
            }
        }
        
        [self.mapViewController fireWaitForIdleEvent];
        
        return YES;
    }
    return NO;
}

- (void) onOverlayLayerChanged
{
    [self updateOverlayLayer];
}

- (void) onOverlayLayerAlphaChanged
{
    [self.mapViewController runWithRenderSync:^{
        OsmAnd::MapLayerConfiguration config;
        config.setOpacityFactor(self.app.data.overlayAlpha);
        [self.mapView setMapLayerConfiguration:self.layerIndex configuration:config forcedUpdate:NO];
    }];
}

- (void) updateOverlayLayer
{
    [self.mapViewController runWithRenderSync:^{
        if (![self updateLayer])
        {
            [self.mapView resetProviderFor:self.layerIndex];
            _rasterOverlayMapProvider.reset();
        }
    }];
}

@end
