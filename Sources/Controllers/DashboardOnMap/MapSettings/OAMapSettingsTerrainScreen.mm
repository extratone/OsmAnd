//
//  OAMapSettingsTerrainScreen.m
//  OsmAnd Maps
//
//  Created by igor on 20.11.2019.
//  Copyright © 2019 OsmAnd. All rights reserved.
//

#import "OAMapSettingsTerrainScreen.h"
#import "OAMapSettingsTerrainParametersViewController.h"
#import "OAMapSettingsViewController.h"
#import "OAMapStyleSettings.h"
#import "Localization.h"
#import "OAColors.h"
#import "OATableDataModel.h"
#import "OATableSectionData.h"
#import "OATableRowData.h"
#import "OARightIconTableViewCell.h"
#import "OASwitchTableViewCell.h"
#import "OAValueTableViewCell.h"
#import "OASimpleTableViewCell.h"
#import "OAButtonTableViewCell.h"
#import "OAImageTextViewCell.h"
#import "OARootViewController.h"
#import "OAMapPanelViewController.h"
#import "OAMapViewController.h"
#import "OAResourcesUIHelper.h"
#import "OAChoosePlanHelper.h"
#import "OAIAPHelper.h"
#import "OAPluginPopupViewController.h"
#import "OAOsmandDevelopmentPlugin.h"
#import "OAManageResourcesViewController.h"
#import "OAAutoObserverProxy.h"
#import "OALinks.h"
#import "OASizes.h"
#import "OADownloadingCellHelper.h"
#import <SafariServices/SafariServices.h>

typedef OsmAnd::ResourcesManager::ResourceType OsmAndResourceType;

@interface OAMapSettingsTerrainScreen() <SFSafariViewControllerDelegate, UITextViewDelegate, OATerrainParametersDelegate>

@end

@implementation OAMapSettingsTerrainScreen
{
    OsmAndAppInstance _app;
    OAIAPHelper *_iapHelper;
    OAOsmandDevelopmentPlugin *_plugin;
    
    OATableDataModel *_data;
    NSInteger _availableMapsSection;
    NSInteger _minZoom;
    NSInteger _maxZoom;
    
    NSObject *_dataLock;
    NSArray<OAResourceItem *> *_mapItems;
    
    OAAutoObserverProxy* _downloadTaskProgressObserver;
    OAAutoObserverProxy* _downloadTaskCompletedObserver;
    OAAutoObserverProxy* _localResourcesChangedObserver;
}

@synthesize settingsScreen, tableData, vwController, tblView, title, isOnlineMapSource;

-(id)initWithTable:(UITableView *)tableView viewController:(OAMapSettingsViewController *)viewController
{
    self = [super init];
    if (self)
    {
        _app = [OsmAndApp instance];
        _iapHelper = [OAIAPHelper sharedInstance];
        _plugin = (OAOsmandDevelopmentPlugin *) [OAPlugin getPlugin:OAOsmandDevelopmentPlugin.class];
        
        settingsScreen = EMapSettingsScreenTerrain;
        
        vwController = viewController;
        tblView = tableView;
        tblView.sectionHeaderHeight = UITableViewAutomaticDimension;
        tblView.sectionFooterHeight = UITableViewAutomaticDimension;
        _dataLock = [[NSObject alloc] init];
        
        [self setupView];
        [self initData];
        [self setupDownloadingCellHelper];
    }
    return self;
}

- (void) initData
{
    _data = [OATableDataModel model];
    
    EOATerrainType type = _app.data.terrainType;
    
    double alphaValue = type == EOATerrainTypeSlope ? _app.data.slopeAlpha : _app.data.hillshadeAlpha;
    NSString *alphaValueString = [NSString stringWithFormat:@"%.0f%@", alphaValue * 100, @"%"];
    
    _minZoom = type == EOATerrainTypeHillshade ? _app.data.hillshadeMinZoom : _app.data.slopeMinZoom;
    _maxZoom = type == EOATerrainTypeHillshade ? _app.data.hillshadeMaxZoom : _app.data.slopeMaxZoom;
    NSString *zoomRangeString = [NSString stringWithFormat:@"%ld-%ld", (long)_minZoom, (long)_maxZoom];
    
    BOOL isRelief3D = [OAIAPHelper isOsmAndProAvailable];
    
    OATableSectionData *switchSection = [_data createNewSection];
    [switchSection addRowFromDictionary:@{
        kCellKeyKey : @"terrainStatus",
        kCellTypeKey : [OASwitchTableViewCell getCellIdentifier],
        kCellTitleKey : type != EOATerrainTypeDisabled ? OALocalizedString(@"shared_string_enabled") : OALocalizedString(@"rendering_value_disabled_name"),
        kCellIconNameKey : type != EOATerrainTypeDisabled ? @"ic_custom_show.png" : @"ic_custom_hide.png",
        kCellIconTint : @(type != EOATerrainTypeDisabled ? color_chart_orange : color_tint_gray),
        @"value" : @(type != EOATerrainTypeDisabled)
    }];
    
    if (type == EOATerrainTypeDisabled)
    {
        OATableSectionData *disabledSection = [_data createNewSection];
        [disabledSection addRowFromDictionary:@{
            kCellKeyKey : @"disabledImage",
            kCellTypeKey : [OAImageTextViewCell getCellIdentifier],
            kCellDescrKey : OALocalizedString(@"enable_hillshade"),
            kCellIconNameKey : @"img_empty_state_terrain"
        }];
        [disabledSection addRowFromDictionary:@{
            kCellKeyKey : @"readMore",
            kCellTypeKey : [OARightIconTableViewCell getCellIdentifier],
            kCellTitleKey : OALocalizedString(@"shared_string_read_more"),
            kCellIconNameKey : @"ic_custom_safari",
            @"link" : kOsmAndFeaturesContourLinesPlugin
        }];
    }
    else
    {
        OATableSectionData *titleSection = [_data createNewSection];
        [titleSection addRowFromDictionary:@{
            kCellKeyKey : @"terrainType",
            kCellTypeKey : [OAValueTableViewCell getCellIdentifier],
            kCellTitleKey : OALocalizedString(@"srtm_color_scheme"),
            @"value" : type == EOATerrainTypeHillshade ? OALocalizedString(@"shared_string_hillshade") : OALocalizedString(@"shared_string_slope")
        }];
        [titleSection addRowFromDictionary:@{
            kCellKeyKey : @"terrainTypeDesc",
            kCellTypeKey : [OASimpleTableViewCell getCellIdentifier],
            kCellDescrKey : type == EOATerrainTypeHillshade ? OALocalizedString(@"map_settings_hillshade_description") : OALocalizedString(@"map_settings_slopes_description"),
            
        }];
        if (_app.data.terrainType == EOATerrainTypeSlope)
        {
            [titleSection addRowFromDictionary:@{
                kCellTypeKey : [OAImageTextViewCell getCellIdentifier],
                kCellDescrKey : OALocalizedString(@"map_settings_slopes_legend"),
                kCellIconNameKey : @"img_legend_slope",
                @"link" : kUrlWikipediaSlope
            }];
        }
        [titleSection addRowFromDictionary:@{
            kCellKeyKey : @"visibility",
            kCellTypeKey : [OAValueTableViewCell getCellIdentifier],
            kCellTitleKey : OALocalizedString(@"visibility"),
            kCellIconNameKey : @"ic_custom_visibility",
            kCellIconTint : @(color_tint_gray),
            @"value" : alphaValueString
        }];
        [titleSection addRowFromDictionary:@{
            kCellKeyKey : @"zoomLevels",
            kCellTypeKey : [OAValueTableViewCell getCellIdentifier],
            kCellTitleKey : OALocalizedString(@"shared_string_zoom_levels"),
            kCellIconNameKey : @"ic_custom_overlay_map",
            kCellIconTint : @(color_tint_gray),
            @"value" : zoomRangeString
        }];
        OATableSectionData *relief3DSection = [_data createNewSection];
        [relief3DSection addRowFromDictionary:@{
            kCellKeyKey : @"relief3D",
            kCellTypeKey : isRelief3D ? [OASwitchTableViewCell getCellIdentifier] : [OAButtonTableViewCell getCellIdentifier],
            kCellTitleKey : OALocalizedString(@"shared_string_relief_3d"),
            kCellIconNameKey : @"ic_custom_3d_relief",
            kCellIconTint : @(![_plugin.enable3DMaps get] || !isRelief3D ? color_tint_gray : color_chart_orange),
            kCellSecondaryIconName : @"ic_payment_label_pro",
            @"value" : @([_plugin.enable3DMaps get]),
        }];
        OATableSectionData *cacheSection = [_data createNewSection];
        cacheSection.footerText = type == EOATerrainTypeHillshade ? OALocalizedString(@"map_settings_add_maps_hillshade") : OALocalizedString(@"map_settings_add_maps_slopes");
        [cacheSection addRowFromDictionary:@{
            kCellKeyKey : @"cache",
            kCellTypeKey : [OAValueTableViewCell getCellIdentifier],
            kCellTitleKey : OALocalizedString(@"shared_string_cache"),
            kCellIconNameKey : @"ic_custom_storage",
            kCellIconTint : @(color_tint_gray),
            @"value" : @"300 MB",
        }];
        if (_mapItems.count > 0)
        {
            OATableSectionData *availableMapsSection = [_data createNewSection];
            _availableMapsSection = [_data sectionCount] - 1;
            availableMapsSection.headerText = OALocalizedString(@"available_maps");
            availableMapsSection.footerText = type == EOATerrainTypeHillshade ? OALocalizedString(@"map_settings_add_maps_hillshade") : OALocalizedString(@"map_settings_add_maps_slopes");
            for (NSInteger i = 0; i < _mapItems.count; i++)
            {
                [availableMapsSection addRowFromDictionary:@{
                    kCellKeyKey : @"mapItem",
                    kCellTypeKey : @"mapItem"
                }];
            }
        }
        else
        {
            _availableMapsSection = -1;
        }
    }
}

- (void)updateAvailableMaps
{
    CLLocationCoordinate2D loc = [OAResourcesUIHelper getMapLocation];
    OsmAnd::ResourcesManager::ResourceType resType = OsmAndResourceType::GeoTiffRegion;
    _mapItems = [OAResourcesUIHelper findIndexItemsAt:loc
                                                 type:resType
                                    includeDownloaded:NO
                                                limit:-1
                                  skipIfOneDownloaded:YES];

    [self initData];
    [UIView transitionWithView:tblView
                      duration:.35
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^(void)
     {
        [self.tblView reloadData];
     }
                    completion:nil];
}

- (void) setupView
{
    title = OALocalizedString(@"shared_string_terrain");

    [_downloadingCellHelper updateAvailableMaps];
}

- (void)onRotation
{
    tblView.separatorInset = UIEdgeInsetsMake(0, [OAUtilities getLeftMargin] + 16, 0, 0);
    [tblView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [_data sectionDataForIndex:section].headerText;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return [_data sectionDataForIndex:section].footerText;
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return [_data sectionCount];
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_data rowCount:section];
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OATableRowData *item = [_data itemForIndexPath:indexPath];
    if ([item.cellType isEqualToString:[OASwitchTableViewCell getCellIdentifier]])
    {
        OASwitchTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:[OASwitchTableViewCell getCellIdentifier]];
        if (cell == nil)
        {
            NSArray *nib = [[NSBundle mainBundle] loadNibNamed:[OASwitchTableViewCell getCellIdentifier] owner:self options:nil];
            cell = (OASwitchTableViewCell *) nib[0];
            [cell descriptionVisibility:NO];
        }
        if (cell)
        {
            cell.titleLabel.text = item.title;
            cell.leftIconView.image = [UIImage templateImageNamed:item.iconName];
            cell.leftIconView.tintColor = UIColorFromRGB(item.iconTint);
            [cell.switchView setOn:[item boolForKey:@"value"]];
            cell.switchView.tag = indexPath.section << 10 | indexPath.row;
            [cell.switchView removeTarget:self action:NULL forControlEvents:UIControlEventValueChanged];
            [cell.switchView addTarget:self action:@selector(mapSettingSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        }
        return cell;
    }
    else if ([item.cellType isEqualToString:[OAValueTableViewCell getCellIdentifier]])
    {
        OAValueTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:[OAValueTableViewCell getCellIdentifier]];
        BOOL isTerrainTypeCell = [item.key isEqualToString:@"terrainType"];
        if (cell == nil)
        {
            NSArray *nib = [[NSBundle mainBundle] loadNibNamed:[OAValueTableViewCell getCellIdentifier] owner:self options:nil];
            cell = (OAValueTableViewCell *) nib[0];
            [cell descriptionVisibility:NO];
        }
        if (cell)
        {
            [cell setCustomLeftSeparatorInset:isTerrainTypeCell];
            if (isTerrainTypeCell)
                cell.separatorInset = UIEdgeInsetsMake(0., CGFLOAT_MAX, 0., 0.);
            else
                cell.separatorInset = UIEdgeInsetsZero;
            
            cell.titleLabel.text = item.title;
            cell.valueLabel.text = [item stringForKey:@"value"];
            [cell leftIconVisibility:item.iconName.length > 0];
            cell.leftIconView.image = [UIImage templateImageNamed:item.iconName];
            cell.leftIconView.tintColor = UIColorFromRGB(item.iconTint);
            cell.accessoryType = ![item.key isEqualToString:@"cache"] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        }
        return cell;
    }
    else if ([item.cellType isEqualToString:[OASimpleTableViewCell getCellIdentifier]])
    {
        OASimpleTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:[OASimpleTableViewCell getCellIdentifier]];
        if (cell == nil)
        {
            NSArray *nib = [[NSBundle mainBundle] loadNibNamed:[OASimpleTableViewCell getCellIdentifier] owner:self options:nil];
            cell = (OASimpleTableViewCell *) nib[0];
            [cell leftIconVisibility:NO];
            [cell titleVisibility:NO];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        if (cell)
        {
            cell.descriptionLabel.text = item.descr;
        }
        return cell;
    }
    else if ([item.cellType isEqualToString:[OAButtonTableViewCell getCellIdentifier]])
    {
        OAButtonTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:[OAButtonTableViewCell getCellIdentifier]];
        if (cell == nil)
        {
            NSArray *nib = [[NSBundle mainBundle] loadNibNamed:[OAButtonTableViewCell getCellIdentifier] owner:self options:nil];
            cell = (OAButtonTableViewCell *) nib[0];
            [cell.button setTitle:nil forState:UIControlStateNormal];
            [cell descriptionVisibility:NO];
        }
        if (cell)
        {
            cell.titleLabel.text = item.title;
            cell.leftIconView.image = [UIImage templateImageNamed:item.iconName];
            cell.leftIconView.tintColor = UIColorFromRGB(item.iconTint);
            
            UIButtonConfiguration *conf = [UIButtonConfiguration plainButtonConfiguration];
            cell.button.configuration = conf;
            [cell.button setImage:[UIImage imageNamed:item.secondaryIconName] forState:UIControlStateNormal];
            
            [cell.button removeTarget:nil action:NULL forControlEvents:UIControlEventTouchUpInside];
            [cell.button addTarget:self action:@selector(showChoosePlanScreen) forControlEvents:UIControlEventTouchUpInside];
        }
        return cell;
    }
    else if ([item.cellType isEqualToString:[OARightIconTableViewCell getCellIdentifier]])
    {
        OARightIconTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:[OARightIconTableViewCell getCellIdentifier]];
        if (cell == nil)
        {
            NSArray *nib = [[NSBundle mainBundle] loadNibNamed:[OARightIconTableViewCell getCellIdentifier] owner:self options:nil];
            cell = (OARightIconTableViewCell *) nib[0];
            cell.leftIconView.tintColor = UIColorFromRGB(color_tint_gray);
            cell.rightIconView.tintColor = UIColorFromRGB(color_primary_purple);
        }
        if (cell)
        {
            if ([item.key isEqualToString:@"mapItem"])
            {
                [cell leftIconVisibility:YES];
                [cell descriptionVisibility:YES];

                OAResourceItem *mapItem = _mapItems[indexPath.row];
                cell.leftIconView.image = [UIImage templateImageNamed:@"ic_custom_terrain"];
                cell.titleLabel.text = mapItem.title;
                cell.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
                cell.descriptionLabel.text = [NSString stringWithFormat:@"%@  •  %@", [OAResourceType resourceTypeLocalized:mapItem.resourceType],
                                              [NSByteCountFormatter stringFromByteCount:mapItem.sizePkg countStyle:NSByteCountFormatterCountStyleFile]];

                if (![_iapHelper.srtm isActive] && (mapItem.resourceType == OsmAndResourceType::HillshadeRegion || mapItem.resourceType == OsmAndResourceType::SlopeRegion))
                    mapItem.disabled = YES;

                if (!mapItem.downloadTask)
                {
                    cell.accessoryView = nil;
                    cell.titleLabel.textColor = !mapItem.disabled ? UIColor.blackColor : UIColorFromRGB(color_text_footer);
                    cell.rightIconView.image = [UIImage templateImageNamed:@"ic_custom_download"];
                }
                else
                {
                    cell.titleLabel.textColor = UIColor.blackColor;
                    cell.rightIconView.image = nil;
                    if (!cell.accessoryView)
                    {
                        FFCircularProgressView *progressView = [[FFCircularProgressView alloc] initWithFrame:CGRectMake(0., 0., 25., 25.)];
                        progressView.iconView = [[UIView alloc] init];
                        progressView.tintColor = UIColorFromRGB(color_primary_purple);
                        cell.accessoryView = progressView;
                    }
                    [self updateDownloadingCell:cell indexPath:indexPath];
                }
            }
            else
            {
                cell.accessoryView = nil;
                BOOL isReadMore = [item.key isEqualToString:@"readMore"];
                [cell leftIconVisibility:!isReadMore];
                [cell descriptionVisibility:!isReadMore];
                cell.titleLabel.textColor = isReadMore ? UIColorFromRGB(color_primary_purple) : UIColor.blackColor;
                cell.titleLabel.font = [UIFont scaledSystemFontOfSize:17. weight:isReadMore ? UIFontWeightSemibold : UIFontWeightRegular];
                cell.rightIconView.image = [UIImage templateImageNamed:item.iconName];
                cell.titleLabel.text = item.title;
            }
        }
        return cell;
    }
    else if ([item.cellType isEqualToString:[OAImageTextViewCell getCellIdentifier]])
    {
        OAImageTextViewCell *cell = [tableView dequeueReusableCellWithIdentifier:[OAImageTextViewCell getCellIdentifier]];
        if (cell == nil)
        {
            NSArray *nib = [[NSBundle mainBundle] loadNibNamed:[OAImageTextViewCell getCellIdentifier] owner:self options:nil];
            cell = (OAImageTextViewCell *) nib[0];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            [cell showExtraDesc:NO];
            cell.descView.delegate = self;
        }
        if (cell)
        {
            cell.separatorInset = UIEdgeInsetsMake(0, [OAUtilities getLeftMargin] + kPaddingOnSideOfContent, 0, 0);
            cell.iconView.image = [UIImage rtlImageNamed:item.iconName];

            BOOL isDisabled = [item.key isEqualToString:@"disabledImage"];
            NSString *descr = item.descr;
            if (isDisabled)
            {
                cell.descView.attributedText = nil;
                cell.descView.text = descr;
            }
            else if (descr && descr.length > 0)
            {
                NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithString:descr attributes:@{
                    NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]
                }];
                NSRange range = [descr rangeOfString:@" " options:NSBackwardsSearch];
                if (range.location != NSNotFound)
                {
                    NSDictionary *linkAttributes = @{ NSLinkAttributeName : [item stringForKey:@"link"] };
                    [str setAttributes:linkAttributes range:NSMakeRange(range.location + 1, descr.length - range.location - 1)];
                }
                cell.descView.text = nil;
                cell.descView.attributedText = str;
            }
            else
            {
                cell.descView.text = nil;
                cell.descView.attributedText = nil;
            }

            if ([cell needsUpdateConstraints])
                [cell setNeedsUpdateConstraints];
        }
        return cell;
    }
    return nil;
}

#pragma mark - UITableViewDelegate

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tblView deselectRowAtIndexPath:indexPath animated:YES];

    OATableRowData *item =  [_data itemForIndexPath:indexPath];

    OAMapSettingsTerrainParametersViewController *terrainParametersScreen;
    if ([item.key isEqualToString:@"visibility"])
        terrainParametersScreen = [[OAMapSettingsTerrainParametersViewController alloc] initWithSettingsType:EOATerrainSettingsTypeVisibility];
    else if ([item.key isEqualToString:@"zoomLevels"])
        terrainParametersScreen = [[OAMapSettingsTerrainParametersViewController alloc] initWithSettingsType:EOATerrainSettingsTypeZoomLevels];
    if (terrainParametersScreen)
    {
        [vwController hide:YES animated:YES];
        terrainParametersScreen.delegate = self;
        [OARootViewController.instance.mapPanel showScrollableHudViewController:terrainParametersScreen];
    }
    else if ([item.key isEqualToString:@"readMore"])
    {
        SFSafariViewController *safariViewController = [[SFSafariViewController alloc] initWithURL:[NSURL URLWithString:[item stringForKey:@"link"]]];
        [self.vwController presentViewController:safariViewController animated:YES completion:nil];
    }
    else if ([item.key isEqualToString:@"mapItem"])
    {
        [_downloadingCellHelper onItemClicked:indexPath];
    }
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point
{
    OATableRowData *item = [_data itemForIndexPath:indexPath];
    if ([item.key isEqualToString:@"terrainType"])
    {
        NSMutableArray<UIMenuElement *> *menuElements = [NSMutableArray array];
        
        UIAction *hillshad = [UIAction actionWithTitle:OALocalizedString(@"shared_string_hillshade")
                                                 image:_app.data.terrainType == EOATerrainTypeHillshade ? [UIImage systemImageNamed:@"checkmark"] : nil
                                            identifier:nil
                                               handler:^(__kindof UIAction * _Nonnull action) {
            [_app.data setTerrainType: EOATerrainTypeHillshade];
            [self terrainTypeChanged];
        }];
        [menuElements addObject:hillshad];
        
        UIAction *slope = [UIAction actionWithTitle:OALocalizedString(@"shared_string_slope")
                                              image:_app.data.terrainType == EOATerrainTypeSlope ? [UIImage systemImageNamed:@"checkmark"] : nil
                                         identifier:nil
                                            handler:^(__kindof UIAction * _Nonnull action) {
            [_app.data setTerrainType: EOATerrainTypeSlope];
            [self terrainTypeChanged];
        }];
        [menuElements addObject:slope];
        UIMenu *contextMenu = [UIMenu menuWithChildren:menuElements];
        return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                       previewProvider:nil
                                                        actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
            return contextMenu;
        }];
    }
    return nil;
}

#pragma mark - UITextViewDelegate

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)URL inRange:(NSRange)characterRange interaction:(UITextItemInteraction)interaction
{
    SFSafariViewController *safariViewController = [[SFSafariViewController alloc] initWithURL:URL];
    [self.vwController presentViewController:safariViewController animated:YES completion:nil];
    return NO;
}

#pragma mark - SFSafariViewControllerDelegate

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller
{
    [controller dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - OATerrainParametersDelegate

- (void)onBackTerrainParameters
{
    [[OARootViewController instance].mapPanel showTerrainScreen];
}

#pragma mark - Selectors

- (void)mapSettingSwitchChanged:(UISwitch *)switchView
{
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:switchView.tag & 0x3FF inSection:switchView.tag >> 10];
    OATableRowData *item = [_data itemForIndexPath:indexPath];
    BOOL isOn = switchView.isOn;
    
    if ([item.key isEqualToString:@"terrainStatus"])
    {
        if (isOn)
        {
            EOATerrainType prevType = _app.data.lastTerrainType;
            [_app.data setTerrainType:prevType != EOATerrainTypeDisabled ? prevType : EOATerrainTypeHillshade];
        }
        else
        {
            _availableMapsSection = -1;
            _app.data.lastTerrainType = _app.data.terrainType;
            [_app.data setTerrainType:EOATerrainTypeDisabled];
        }
    }
    else if ([item.key isEqualToString:@"relief3D"])
    {
        [_plugin.enable3DMaps set:isOn];
    }
    
    [self updateAvailableMaps];
}

- (void)showChoosePlanScreen
{
    [OAChoosePlanHelper showChoosePlanScreen:[OARootViewController instance].navigationController];
}

- (void) terrainTypeChanged
{
    _availableMapsSection = -1;
    [self updateAvailableMaps];
}

@end
