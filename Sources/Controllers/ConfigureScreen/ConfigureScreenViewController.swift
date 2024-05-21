//
//  ConfigureScreenViewController.swift
//  OsmAnd Maps
//
//  Created by Paul on 18.05.2023.
//  Copyright © 2023 OsmAnd. All rights reserved.
//

import UIKit
import Foundation

@objc(OAWidgetStateDelegate)
protocol WidgetStateDelegate: AnyObject {
    func onWidgetStateChanged()
}

@objc(OAConfigureScreenViewController)
@objcMembers
class ConfigureScreenViewController: OABaseNavbarViewController, AppModeSelectionDelegate, WidgetStateDelegate {

    private static let selectedKey = "selected"
    private let kWidgetsInfoKey = "widget_info"
    
    private var widgetRegistry: OAMapWidgetRegistry?
    private var appMode: OAApplicationMode! {
        didSet {
            setupNavbarButtons()
        }
    }
    
    override func registerObservers() {
        addNotification(NSNotification.Name(kWidgetVisibilityChangedMotification), selector: #selector(onWidgetStateChanged))
    }
    
    override func generateData() {
        tableData.clearAllData()
        widgetRegistry = OARootViewController.instance().mapPanel.mapWidgetRegistry
        let settings = OAAppSettings.sharedManager()!
        appMode = settings.applicationMode.get()
        
        let widgetsSection = tableData!.createNewSection()
        widgetsSection.headerText = localizedString("shared_string_widgets")
        widgetsSection.footerText = localizedString("widget_panels_descr")
        for panel in WidgetsPanel.values {
            let widgetsCount = getWidgetsCount(panel: panel)
            let row = widgetsSection.createNewRow()
            row.cellType = OAValueTableViewCell.getIdentifier()
            row.title = panel.title
            row.iconName = panel.iconName
            row.setObj(panel, forKey: "panel")
            row.iconTintColor = (widgetsCount == 0) ? UIColor.iconColorDefault : UIColor(rgb: Int(appMode!.getIconColor()));
            row.descr = String(widgetsCount)
            row.accessibilityLabel = panel.title
            row.accessibilityValue = String(format: localizedString("ltr_or_rtl_combine_via_colon"), localizedString("shared_string_widgets"), String(widgetsCount))
            if panel == WidgetsPanel.values.last {
                row.setObj(NSNumber(true), forKey: "isCustomLeftSeparatorInset")
            }
        }
        let transparencyRow = widgetsSection.createNewRow()
        transparencyRow.title = localizedString("map_widget_transparent")
        transparencyRow.key = "map_widget_transparent"
        transparencyRow.accessibilityLabel = localizedString("map_widget_transparent")
        transparencyRow.setObj(NSNumber(value: settings.transparentMapTheme.get()), forKey: Self.selectedKey)
        transparencyRow.cellType = OASwitchTableViewCell.getIdentifier()
        
        let buttonsSection = tableData!.createNewSection()
        buttonsSection.headerText = localizedString("shared_string_buttons")
        populateCompassRow(buttonsSection.createNewRow())
        let distByTapRow = buttonsSection.createNewRow()
        distByTapRow.title = localizedString("map_widget_distance_by_tap")
        distByTapRow.iconName = "ic_action_ruler_line"
        distByTapRow.iconTint = Int(appMode!.getIconColor())
        distByTapRow.key = "map_widget_distance_by_tap"
        distByTapRow.accessibilityLabel = distByTapRow.title
        distByTapRow.accessibilityLabel = settings.showDistanceRuler.get() ? localizedString("shared_string_on") : localizedString("shared_string_off")
        distByTapRow.setObj(NSNumber(value: settings.showDistanceRuler.get()), forKey: Self.selectedKey)
        distByTapRow.cellType = OASwitchTableViewCell.getIdentifier()
        
        let quickActionsCount = OAQuickActionRegistry.sharedInstance().getQuickActionsCount()
        let quickActionsEnabled = settings.quickActionIsOn.get()
        let actionsString = quickActionsEnabled ? String(quickActionsCount) : localizedString("shared_string_off")
        let quickActionRow = buttonsSection.createNewRow()
        quickActionRow.title = localizedString("configure_screen_quick_action")
        quickActionRow.descr = quickActionsEnabled ? String(format: localizedString("ltr_or_rtl_combine_via_colon"),
                                                            localizedString("shared_string_actions"),
                                                            actionsString) : actionsString
        quickActionRow.iconTintColor = quickActionsEnabled ? UIColor(rgb: Int(appMode!.getIconColor())) : UIColor.iconColorDefault
        quickActionRow.key = "quick_action"
        quickActionRow.iconName = "ic_custom_quick_action"
        quickActionRow.cellType = OAValueTableViewCell.getIdentifier()
        quickActionRow.accessibilityLabel = quickActionRow.title
        quickActionRow.accessibilityValue = quickActionRow.descr
        
        let map3dModeRow = buttonsSection.createNewRow()
        let selected3dMode = OAAppSettings.sharedManager()!.map3dMode.get()
        let isMap3DVisible = settings.map3dMode.get() == .visible || settings.map3dMode.get() == .visibleIn3DMode
        map3dModeRow.key = "map_3d_mode"
        map3dModeRow.title = localizedString("map_3d_mode_action")
        map3dModeRow.descr = OAMap3DModeVisibility.getTitle(selected3dMode) ?? ""
        map3dModeRow.iconTintColor = isMap3DVisible ? UIColor(rgb: Int(appMode!.getIconColor())) : UIColor.iconColorDefault
        map3dModeRow.iconName = OAMap3DModeVisibility.getIconName(selected3dMode)
        map3dModeRow.cellType = OAValueTableViewCell.getIdentifier()
        map3dModeRow.accessibilityLabel = map3dModeRow.title
        map3dModeRow.accessibilityValue = map3dModeRow.descr
        
        let speedomenterRow = buttonsSection.createNewRow()
        speedomenterRow.cellType = OAValueTableViewCell.getIdentifier()
        speedomenterRow.key = "shared_string_speedometer"
        speedomenterRow.title = localizedString("shared_string_speedometer")
        speedomenterRow.descr = settings.showSpeedometer.get() ? localizedString("shared_string_on") : localizedString("shared_string_off")
        speedomenterRow.accessibilityLabel = speedomenterRow.title
        speedomenterRow.accessibilityValue = speedomenterRow.descr
        if settings.showSpeedometer.get() {
            if settings.nightMode {
                speedomenterRow.iconName = "widget_speed_night"
            } else {
                speedomenterRow.iconName = "widget_speed_day"
            }
            speedomenterRow.iconTintColor = nil
        } else {
            speedomenterRow.iconName = "ic_custom_speedometer_outlined"
            speedomenterRow.iconTintColor = UIColor.iconColorDefault
        }
    }
    
    func populateCompassRow(_ row: OATableRowData) {
        let compassMode = EOACompassMode(rawValue: Int(OAAppSettings.sharedManager()!.compassMode.get()))!
        let descr = OACompassMode.getTitle(compassMode) ?? ""
        let title = localizedString("map_widget_compass")
        
        row.title = title
        row.descr = descr
        row.accessibilityLabel = title
        row.accessibilityValue = descr
        row.key = "compass"
        row.iconTintColor = appMode != nil ? UIColor(rgb: Int(appMode!.getIconColor())) : UIColor.iconColorDefault
        row.iconName = OACompassMode.getIconName(compassMode)
        row.cellType = OAValueTableViewCell.getIdentifier()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func getTitle() -> String! {
        localizedString("layer_map_appearance")
    }
    
    override func getRightNavbarButtons() -> [UIBarButtonItem]! {
        let button = createRightNavbarButton(nil, iconName: appMode?.getIconName(), action: #selector(onRightNavbarButtonPressed), menu: nil)
        button?.customView?.tintColor = UIColor(rgb: Int(appMode!.getIconColor()))
        button?.accessibilityLabel = localizedString("selected_profile")
        button?.accessibilityValue = appMode?.toHumanString()
        return [button!]
    }
    
    override func onRightNavbarButtonPressed() {
        let modeSelectionVc = AppModeSelectionViewController()
        modeSelectionVc.delegate = self
        let navigationController = UINavigationController()
        navigationController.setViewControllers([modeSelectionVc], animated: true)
        
        navigationController.modalPresentationStyle = .pageSheet
        let sheet = navigationController.sheetPresentationController
        if let sheet
        {
            sheet.detents = [.medium(), .large()]
            sheet.preferredCornerRadius = 20
        }
        self.navigationController?.present(navigationController, animated: true)
    }
    
    override func isNavbarSeparatorVisible() -> Bool {
        false
    }
    
    func getWidgetsCount(panel: WidgetsPanel) -> Int {
        let filter = Int(kWidgetModeEnabled | KWidgetModeAvailable | kWidgetModeMatchingPanels)
        return widgetRegistry!.getWidgetsForPanel(appMode, filterModes: filter, panels: [panel]).count
    }
    
    // MARK: AppModeSelectionDelegate
    func onAppModeSelected(_ appMode: OAApplicationMode) {
        OAAppSettings.sharedManager()!.setApplicationModePref(appMode)
        self.appMode = appMode
        onWidgetStateChanged()
    }
    
    func onNewProfilePressed() {
        let vc = OACreateProfileViewController()
        self.navigationController?.pushViewController(vc, animated: true)
    }
}

// TableView
extension ConfigureScreenViewController {
    
    fileprivate func applyAccessibility(_ cell: UITableViewCell, _ item: OATableRowData) {
        cell.accessibilityLabel = item.accessibilityLabel
        cell.accessibilityValue = item.accessibilityValue
    }
    
    override func getRow(_ indexPath: IndexPath!) -> UITableViewCell! {
        let item = tableData!.item(for: indexPath)
        if item.cellType == OAValueTableViewCell.getIdentifier() {
            var cell = tableView.dequeueReusableCell(withIdentifier: OAValueTableViewCell.getIdentifier()) as? OAValueTableViewCell
            if cell == nil {
                let nib = Bundle.main.loadNibNamed(OAValueTableViewCell.getIdentifier(), owner: self, options: nil)
                cell = nib?.first as? OAValueTableViewCell
                cell?.accessoryType = .disclosureIndicator
                cell?.descriptionVisibility(false)
            }
            if let cell {
                let isCustomLeftSeparatorInset = item.bool(forKey: "isCustomLeftSeparatorInset")
                cell.setCustomLeftSeparatorInset(isCustomLeftSeparatorInset)
                cell.separatorInset = .zero
                cell.valueLabel.text = item.descr
                cell.leftIconView.image = UIImage.templateImageNamed(item.iconName)
                cell.leftIconView.tintColor = item.iconTintColor
                cell.titleLabel.text = item.title
                applyAccessibility(cell, item)
            }
            return cell
        } else if item.cellType == OASwitchTableViewCell.getIdentifier() {
            var cell = tableView.dequeueReusableCell(withIdentifier: OASwitchTableViewCell.getIdentifier()) as? OASwitchTableViewCell
            if cell == nil {
                let nib = Bundle.main.loadNibNamed(OASwitchTableViewCell.getIdentifier(), owner: self, options: nil)
                cell = nib?.first as? OASwitchTableViewCell
                cell?.descriptionVisibility(false)
            }
            if let cell {
                cell.leftIconVisibility(!(item.iconName?.isEmpty ?? true))
                if !cell.leftIconView.isHidden {
                    cell.leftIconView.image = UIImage.templateImageNamed(item.iconName)
                }
                let selected = item.bool(forKey: Self.selectedKey)
                cell.leftIconView.tintColor = selected ? UIColor(rgb: item.iconTint) : UIColor.iconColorDefault
                cell.titleLabel.text = item.title

                cell.switchView.removeTarget(nil, action: nil, for: .allEvents)
                cell.switchView.isOn = selected
                cell.switchView.tag = indexPath.section << 10 | indexPath.row
                cell.switchView.addTarget(self, action: #selector(onSwitchClick(_:)), for: .valueChanged)

                applyAccessibility(cell, item)
                return cell
            }
        }
        return nil
    }
    
    @objc func onSwitchClick(_ sender: Any) -> Bool {
        guard let sw = sender as? UISwitch else {
            return false
        }
        
        let indexPath = IndexPath(row: sw.tag & 0x3FF, section: sw.tag >> 10)
        let data = tableData!.item(for: indexPath)
        
        let settings = OAAppSettings.sharedManager()!
        if data.key == "map_widget_transparent" {
            settings.transparentMapTheme.set(sw.isOn)
            OARootViewController.instance().mapPanel.hudViewController.mapInfoController.updateLayout()
        } else if data.key == "map_widget_distance_by_tap" {
            settings.showDistanceRuler.set(sw.isOn)
            OARootViewController.instance().mapPanel.mapViewController.updateTapRulerLayer()
        }
        
        if let cell = self.tableView.cellForRow(at: indexPath) as? OASwitchTableViewCell, !cell.leftIconView.isHidden {
            UIView.animate(withDuration: 0.2) {
                cell.leftIconView.tintColor = sw.isOn ? UIColor(rgb: Int(settings.applicationMode.get().getIconColor())) : UIColor.iconColorDefault
            }
        }
        
        return false
    }

    override func onRowSelected(_ indexPath: IndexPath!) {
        let data = tableData!.item(for: indexPath)
        if data.key == "quick_action" {
            let vc = OAQuickActionListViewController()!
            vc.delegate = self
            self.navigationController?.pushViewController(vc, animated: true)
        } else if data.key == "compass" {
            let vc = CompassVisibilityViewController()
            vc.delegate = self
            showMediumSheetViewController(vc, isLargeAvailable: false)
        } else if data.key == "map_3d_mode" {
            let vc = Map3dModeButtonVisibilityViewController()
            vc.delegate = self
            showMediumSheetViewController(vc, isLargeAvailable: false)
        } else if data.key == "shared_string_speedometer" {
            let vc = SpeedometerWidgetSettingsViewController()
            vc.delegate = self
            show(vc)
        } else {
            let panel = data.obj(forKey: "panel") as? WidgetsPanel
            if let panel {
                let vc = WidgetsListViewController(widgetPanel: panel)
                show(vc)
            }
        }
    }
    
    // MARK: WidgetStateDelegate
    @objc func onWidgetStateChanged() {
        generateData()
        tableView.reloadData()
    }

}
