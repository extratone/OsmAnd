//
//  OARouteParameterValuesViewController.m
//  OsmAnd
//
//  Created by Paul on 21.08.2020.
//  Copyright © 2020 OsmAnd. All rights reserved.
//

#import "OARouteParameterValuesViewController.h"
#import "OAAppSettings.h"
#import "OARightIconTableViewCell.h"
#import "OARoutingHelper.h"
#import "OARoutePreferencesParameters.h"
#import "OATableViewCustomHeaderView.h"
#import "OATableViewCustomFooterView.h"
#import "OAColors.h"
#import "Localization.h"

#include <generalRouter.h>

#define kGoodsRestrictionsHeaderTopMargin 20

typedef NS_ENUM(NSInteger, EOARouteParamType) {
    EOARouteParamTypeGroup = 0,
    EOARouteParamTypeNumeric
};

@interface OARouteParameterValuesViewController () <UITableViewDelegate, UITableViewDataSource>

@end

@implementation OARouteParameterValuesViewController
{
    RoutingParameter _param;
    OALocalRoutingParameterGroup *_group;
    OALocalRoutingParameter *_parameter;
    OACommonString *_setting;

    OAAppSettings *_settings;
    
    EOARouteParamType _type;
    NSInteger _indexSelected;
    BOOL _isHazmatCategory;
    BOOL _isAnyCategorySelected;
    BOOL _isGoodsRestrictionsCategory;
    
    UIView *_tableHeaderView;
}

- (instancetype) initWithRoutingParameterGroup:(OALocalRoutingParameterGroup *)group appMode:(OAApplicationMode *)mode
{
    self = [super initWithAppMode:mode];
    if (self) {
        [self commonInit];
        _group = group;
        _type = EOARouteParamTypeGroup;
    }
    return self;
}

- (instancetype) initWithRoutingParameter:(OALocalRoutingParameter *)parameter appMode:(OAApplicationMode *)mode
{
    self = [super initWithAppMode:mode];
    if (self)
    {
        _parameter = parameter;
        _type = EOARouteParamTypeNumeric;
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithParameter:(RoutingParameter &)parameter appMode:(OAApplicationMode *)mode
{
    self = [super initWithAppMode:mode];
    if (self)
    {
        [self commonInit];
        _param = parameter;
        _setting = [_settings getCustomRoutingProperty:[NSString stringWithUTF8String:_param.id.c_str()]
                                          defaultValue:_param.type == RoutingParameterType::NUMERIC ? kDefaultNumericValue : kDefaultSymbolicValue];
        _type = EOARouteParamTypeNumeric;
    }
    return self;
}

- (void) commonInit
{
    _settings = [OAAppSettings sharedManager];

    if (_parameter)
    {
        _isHazmatCategory = [_parameter isKindOfClass:OAHazmatRoutingParameter.class];
        _isGoodsRestrictionsCategory = [_parameter isKindOfClass:OAGoodsDeliveryRoutingParameter.class];
        _isAnyCategorySelected = (_isHazmatCategory || _isGoodsRestrictionsCategory) && [_parameter isSelected];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.tableView registerClass:OATableViewCustomFooterView.class
        forHeaderFooterViewReuseIdentifier:[OATableViewCustomFooterView getCellIdentifier]];
    if (_isGoodsRestrictionsCategory)
        [self setupTableHeaderViewWithText:OALocalizedString(@"routing_attr_goods_restrictions_header_name")];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        if (_isGoodsRestrictionsCategory)
            [self setupTableHeaderViewWithText:OALocalizedString(@"routing_attr_goods_restrictions_header_name")];
        [self.tableView reloadData];
    } completion:nil];
}

- (void)applyLocalization
{
    [super applyLocalization];
    self.titleLabel.text = _type == EOARouteParamTypeNumeric
            ? _parameter != nil ? [_parameter getText] : [NSString stringWithUTF8String:_param.name.c_str()]
            : [_group getText];
}

#pragma mark - UITableViewDataSource

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return _isAnyCategorySelected ? 2 : 1;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (_type == EOARouteParamTypeGroup)
        return [_group getRoutingParameters].count;
    else if ((_isHazmatCategory || _isGoodsRestrictionsCategory) && section == 0)
        return 2;

    return _parameter ? _parameter.routingParameter.possibleValues.size() : _param.possibleValues.size();
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *text;
    UIImage *icon;
    UIColor *color;
    BOOL isSelected = NO;

    if (_type == EOARouteParamTypeNumeric)
    {
        if (_isHazmatCategory || _isGoodsRestrictionsCategory)
        {
            if (indexPath.section == 0)
            {
                isSelected = (indexPath.row == 0 && !_isAnyCategorySelected) || (indexPath.row == 1 && _isAnyCategorySelected);
                text = OALocalizedString(indexPath.row == 0 ? @"shared_string_no" : @"shared_string_yes");
            }
            else
            {
                OAHazmatRoutingParameter *parameter = (OAHazmatRoutingParameter *) _parameter;
                NSString *value = [parameter getValue:indexPath.row];
                isSelected = [[_parameter getValue] isEqualToString:value];
                text = value;
            }
        }
        else
        {
            isSelected = [[NSString stringWithFormat:@"%.1f", _param.possibleValues[indexPath.row]] isEqualToString:[_setting get:self.appMode]];
            text = [NSString stringWithUTF8String:_param.possibleValueDescriptions[indexPath.row].c_str()];
        }
    }
    else if (_type == EOARouteParamTypeGroup)
    {
        OALocalRoutingParameter *routeParam = _group.getRoutingParameters[indexPath.row];
        text = [routeParam getText];
        isSelected = _group.getSelected == _group.getRoutingParameters[indexPath.row];
    }

    OARightIconTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:[OARightIconTableViewCell getCellIdentifier]];
    if (cell == nil)
    {
        NSArray *nib = [[NSBundle mainBundle] loadNibNamed:[OARightIconTableViewCell getCellIdentifier] owner:self options:nil];
        cell = (OARightIconTableViewCell *) nib[0];
        [cell descriptionVisibility:NO];
        [cell leftIconVisibility:NO];
    }
    if (cell)
    {
        cell.titleLabel.text = text;
        cell.accessoryType = UITableViewCellAccessoryCheckmark;

        if (isSelected)
        {
            _indexSelected = indexPath.row;
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
            if (_isGoodsRestrictionsCategory && _indexSelected == 1)
            {
                [cell descriptionVisibility:YES];
                cell.descriptionLabel.text = OALocalizedString(@"routing_attr_goods_restrictions_yes_desc");
            }
            else
            {
                [cell descriptionVisibility:NO];
                cell.descriptionLabel.text = nil;
            }
        }
        else
        {
            cell.accessoryType = UITableViewCellAccessoryNone;
        }
    }
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (_isHazmatCategory && section == 1)
        return OALocalizedString(@"rendering_value_category_name");

    return nil;
}

#pragma mark - UITableViewDelegate

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_type == EOARouteParamTypeNumeric)
    {
        if ((_isHazmatCategory || _isGoodsRestrictionsCategory) && indexPath.section == 0)
        {
            BOOL isAnyCategorySelected = _isAnyCategorySelected;
            _isAnyCategorySelected = indexPath.row == 1;
            if (isAnyCategorySelected == _isAnyCategorySelected)
                return;
            else
                [_parameter setSelected:_isAnyCategorySelected];
        }
        else
        {
            if (_isHazmatCategory)
                [(OAHazmatRoutingParameter *) _parameter setValue:indexPath.row];
            else
                [_setting set:[NSString stringWithFormat:@"%.1f", _param.possibleValues[indexPath.row]] mode:self.appMode];
        }
    }
    else if (_type == EOARouteParamTypeGroup)
    {
        OALocalRoutingParameter *useElevation = nil;
        if (_group.getRoutingParameters.count > 0
                && ([[NSString stringWithUTF8String:_group.getRoutingParameters.firstObject.routingParameter.id.c_str()] isEqualToString:kRouteParamIdHeightObstacles]))
            useElevation = _group.getRoutingParameters.firstObject;
        BOOL anySelected = NO;

        for (NSInteger i = 0; i < _group.getRoutingParameters.count; i++)
        {
            OALocalRoutingParameter *param = _group.getRoutingParameters[i];
            if (i == indexPath.row && param == useElevation)
                anySelected = YES;

            [param setSelected:i == indexPath.row && !anySelected];
        }
        if (useElevation)
            [useElevation setSelected:!anySelected];
    }
    [OARoutingHelper.sharedInstance recalculateRouteDueToSettingsChange];

    if (self.delegate)
        [self.delegate onSettingsChanged];
    if ((_isHazmatCategory && indexPath.section == 0) || (_isGoodsRestrictionsCategory && indexPath.section == 0))
        [self.tableView reloadData];
    else
        [self dismissViewController];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    return [OATableViewCustomHeaderView getHeight:title width:tableView.bounds.size.width] + kGoodsRestrictionsHeaderTopMargin;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    if (!(_type == EOARouteParamTypeGroup || ((_isHazmatCategory || _isGoodsRestrictionsCategory) && section == 0)))
        return 0.001;

    NSString *footer = @"";
    if (_type == EOARouteParamTypeGroup)
    {
        OALocalRoutingParameter *param = _group.getRoutingParameters[_indexSelected];
        footer = [param getDescription];
    }
    else if (_isHazmatCategory || _isGoodsRestrictionsCategory)
    {
        footer = [_parameter getDescription];
    }

    return [OATableViewCustomFooterView getHeight:footer width:self.tableView.bounds.size.width];
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    if (!(_type == EOARouteParamTypeGroup || ((_isHazmatCategory || _isGoodsRestrictionsCategory) && section == 0)))
        return nil;

    NSString *footer = @"";
    if (_type == EOARouteParamTypeGroup)
    {
        OALocalRoutingParameter *param = _group.getRoutingParameters[_indexSelected];
        footer = [param getDescription];
        if (!footer || footer.length == 0)
            return nil;
    }
    else if (_isHazmatCategory || _isGoodsRestrictionsCategory)
    {
        footer = [_parameter getDescription];
    }

    OATableViewCustomFooterView *vw =
            [tableView dequeueReusableHeaderFooterViewWithIdentifier:[OATableViewCustomFooterView getCellIdentifier]];
    UIFont *textFont = [UIFont scaledSystemFontOfSize:13];
    NSMutableAttributedString *textStr = [[NSMutableAttributedString alloc] initWithString:footer attributes:@{
            NSFontAttributeName: textFont,
            NSForegroundColorAttributeName: UIColorFromRGB(color_text_footer)
    }];
    vw.label.attributedText = textStr;
    return vw;
}

@end
