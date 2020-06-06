//
//  SelectTransportController.swift
//  CityTransportGuide
//
//  Created by Alexandr Nadtoka on 11/2/18.
//  Copyright © 2018 kreatimont. All rights reserved.
//

import UIKit
import Localize_Swift
import GoogleMobileAds

protocol SelectTransportControllerDelegate: class {
    
    func willChangeState(_ controller: SelectTransportController, expanded: Bool)
    func didChangeState(_ controller: SelectTransportController, expanded: Bool)
    
    func willSelectTransport(with id: Int)
    func didSelectTransport(with id: Int)
    
    func willDeselectTransport(with id: Int)
    func didDeselectTransport(with id: Int)
    
}

class SelectTransportController: UIViewController {
    
    //MARK: - views
    
    private lazy var collectionViewForSelected: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = self.interitemSpace
        layout.minimumLineSpacing = self.interitemSpace
        layout.scrollDirection = .horizontal
        let _collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
        _collectionView.backgroundColor = .clear
        _collectionView.tag = self.selectedCollectionViewTag
        _collectionView.dataSource = self
        _collectionView.delegate = self
        _collectionView.register(TransportCell.self, forCellWithReuseIdentifier: TransportCell.identifier)
        return _collectionView
    }()
    
    private lazy var collectionViewForAll: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = self.interitemSpaceForCVAll
        layout.minimumLineSpacing = self.interitemSpaceForCVAll
        layout.scrollDirection = .vertical
        let _collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
        _collectionView.register(TransportHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: TransportHeader.identifier)
        _collectionView.backgroundColor = .clear
        _collectionView.tag = self.allCollectionViewTag
        _collectionView.dataSource = self
        _collectionView.delegate = self
        _collectionView.register(TransportCell.self, forCellWithReuseIdentifier: TransportCell.identifier)
        return _collectionView
    }()
    
    private lazy var emptyStubForSelected: UIButton = {
        let helpAddRouteButton = UIButton(type: .custom)
        helpAddRouteButton.frame = self.collectionViewForSelected.bounds
        helpAddRouteButton.setTitle("DragTitle".localized(), for: .normal)
        helpAddRouteButton.setTitleColor(Settings.shared.theme.textColor, for: .normal)
        helpAddRouteButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        helpAddRouteButton.titleLabel?.textAlignment = .center
        helpAddRouteButton.addTarget(self, action: #selector(handleTapAddSelectedCell(_:)), for: .touchUpInside)
        
        return helpAddRouteButton
    }()
    
    private lazy var loadingStubForSelected: LoadingView = {
        let loadingView = LoadingView(indicatorStyle: Settings.shared.theme.activityIndicatorStyle, title: "DownloadingRoutesStatus".localized())
        loadingView.activityIndicatorView.color = Settings.shared.theme.barItemColor
        return loadingView
    }()
    
    private lazy var headerView = UIView()
    
    private lazy var draggableView: DraggableView = {
        let _draggableView = DraggableView()
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        _draggableView.addGestureRecognizer(pan)
        self.panDraggableView = pan
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTapOnDragIndicator(_:)))
        tap.require(toFail: pan)
        _draggableView.addGestureRecognizer(tap)
        return _draggableView
    }()
    
    private lazy var backgroundView: UIView = {
        let view = UIView()
        return view
    }()
    
    //MARK: - properties
    
    private var panDraggableView: UIPanGestureRecognizer?
    private var panHeaderView: UIPanGestureRecognizer?
    private var panCollectionView: UIPanGestureRecognizer?
    
    let impact = UIImpactFeedbackGenerator(style: .light)
    
    let selectedCollectionViewTag = 0
    let allCollectionViewTag = 1
    
    let headerHeight: CGFloat = 34
    let additionalDragHiddenHeight: CGFloat = 30
    var collapsedHeight: CGFloat {
        return 50 + additionalDragHiddenHeight
    }
    let interitemSpace: CGFloat = 4
    let interitemSpaceForCVAll: CGFloat = 8
    var numberOfItemsInRowForAll: CGFloat {
        var numberOfItems: CGFloat = 9
        switch UIDevice.current.screenType {
        case .iPhones_5_5s_5c_SE:
            numberOfItems = 8
        case .iPhones_6_6s_7_8, .iPhones_X_XS:
            numberOfItems = 9
        case .iPhones_6Plus_6sPlus_7Plus_8Plus, .iPhone_XSMax, .iPhone_XR:
            numberOfItems = 10
        default: break
        }
        return numberOfItems
    }
    let lineSpace: CGFloat = 6
    
    let sectionInsetsForSelectedCV = UIEdgeInsets(top: 4, left: 2, bottom: 4, right: 2)
    let sectionInsetsForAllCV = UIEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
    
    var maxExpandedHeight: CGFloat {
        guard let window = self.view.window else {
            return self.collapsedHeight + self.collectionViewForAll.contentSize.height
        }
        let yInWindow = self.view.convert(self.view.frame.origin, to: window).y
        let bannerHeight = CTPurchases.isAdsRemoved() ? 0 : (kGADAdSizeBanner.size.height - additionalDragHiddenHeight - 2)
        let maxAvailableHeight = UIScreen.main.bounds.height - (yInWindow + bannerHeight)
        let maxContentHeight = self.collapsedHeight + self.collectionViewForAll.contentSize.height
        return min(maxAvailableHeight, maxContentHeight)
    }
    
    var cellSizeForAllCV: CGSize {
        let availableSpace = self.collectionViewForAll.frame.width - (sectionInsetsForAllCV.left + sectionInsetsForAllCV.right) - (CGFloat(numberOfItemsInRowForAll - 1) * interitemSpaceForCVAll)
        let width  = availableSpace / CGFloat(numberOfItemsInRowForAll)
        let height = width
        return CGSize(width: width, height: height)
    }
    var cellSizeForSelectedCV: CGSize {
        let availableSpace = self.collectionViewForSelected.frame.width - (sectionInsetsForSelectedCV.left + sectionInsetsForSelectedCV.right) - (CGFloat((Constants.maximumNumberOfSelectedRoutes - 1)) * interitemSpace)
        let width  = availableSpace / CGFloat(Constants.maximumNumberOfSelectedRoutes)
        let height = self.collectionViewForSelected.frame.height - (sectionInsetsForSelectedCV.top + sectionInsetsForSelectedCV.bottom)
        return CGSize(width: width, height: height)
    }
    
    var isExpanded: Bool = false
    
    var allRoutes = [Route.Kind: [Route]]() {
        didSet {
            for route in self.selectedRoutes {
                if let color = self.colorForRouteId[route.id] {
                    RoutesColorManager.default.returnColorToAvailable(color)
                    self.colorForRouteId.removeValue(forKey: route.id)
                }
            }
            self.selectedRoutes.removeAll()
            self.allRoutesKeysSorted = Array(allRoutes.keys).sorted{ $0.order < $1.order }
            DispatchQueue.main.async {
                self.collectionViewForSelected.reloadData()
                self.collectionViewForAll.reloadData()
                
                if self.firstOpenInSession && Settings.shared.savePreviousSelectedRoutes {
                    let previousSelectedRoutes = Settings.shared.previousSelectedRoutes
                    if previousSelectedRoutes.count > 0 {
                        CoreDataManager.shared.getRoutes(with: previousSelectedRoutes, city: Settings.shared.city) { (prevRoutes) in
                            DispatchQueue.main.async {
                                for route in prevRoutes {
                                    self.select(route: route)
                                }
                            }
                        }
                    } else {
                        if self.selectedRoutes.count == 0 {
                            self.collectionViewForSelected.backgroundView = self.emptyStubForSelected
                        }
                    }
                } else {
                    if self.selectedRoutes.count == 0 {
                        self.collectionViewForSelected.backgroundView = self.emptyStubForSelected
                    }
                }
                self.firstOpenInSession = false
            }
        }
    }
    
    var selectedRoutes = [Route]()
    
    var selectedRoutesIds: [Int] {
        return self.selectedRoutes.map({ $0.id })
    }
    
    var colorForRouteId = [Int: UIColor]()
    
    var allRoutesKeysSorted = [Route.Kind]()
    
    var firstOpenInSession = true
    
    //MARK: - delegate
    
    weak var delegate: SelectTransportControllerDelegate?
    
    //MARK: - lifecycle
    
    init(routes: [Route]) {
        super.init(nibName: nil, bundle: nil)
        self.allRoutes = self.mutateToDictionary(routes: routes)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        headerView.addSubview(self.collectionViewForSelected)
        collectionViewForSelected.snp.makeConstraints { (make) in
            make.top.equalToSuperview()
            make.left.right.equalToSuperview().inset(4)
            make.bottom.equalToSuperview()
        }
        
        self.view.addSubview(self.headerView)
        self.headerView.snp.makeConstraints { (make) in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(self.headerHeight).priority(.required)
        }
        
        self.view.addSubview(self.collectionViewForAll)
        collectionViewForAll.snp.makeConstraints { (make) in
            make.top.equalTo(self.headerView.snp.bottom)
            make.left.right.equalToSuperview()
            make.height.equalTo(self.collectionViewForAll.contentSize.height).priority(UILayoutPriority.defaultLow)
        }
        
        self.view.addSubview(self.draggableView)
        draggableView.snp.makeConstraints { (make) in
            make.left.right.equalToSuperview()
            make.bottom.equalToSuperview()
            make.top.equalTo(self.collectionViewForAll.snp.bottom)
            make.height.equalTo(self.collapsedHeight - self.headerHeight).priority(.required)
        }
        
        draggableView.visibleHeight = self.collapsedHeight - self.headerHeight - self.additionalDragHiddenHeight
        
        let visibleHeightBottomInset = self.collapsedHeight - self.headerHeight - self.draggableView.visibleHeight
        
        self.view.insertSubview(self.backgroundView, at: 0)
        self.backgroundView.snp.makeConstraints { (make) in
            make.top.left.right.equalToSuperview()
            make.bottom.equalToSuperview().inset(visibleHeightBottomInset)
        }
        
        if selectedRoutesIds.count == 0 {
            self.headerView.layoutSubviews()
            self.collectionViewForSelected.backgroundView = self.emptyStubForSelected
        }
        
        self.view.bringSubviewToFront(self.headerView)
        
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        headerView.addGestureRecognizer(pan)
        self.panHeaderView = pan
        
        let panCV = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        self.collectionViewForAll.addGestureRecognizer(panCV)
        panCV.delegate = self
        self.panCollectionView = panCV
        
        self.collectionViewForAll.panGestureRecognizer.require(toFail: panCV)
        
        NotificationCenter.default.addObserver(self, selector: #selector(didChangedLanguage(_:)), name: Notification.Name.didChangedLanguage, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(didChangedTheme(_:)), name: Notification.Name.didChangedTheme, object: nil)
        self.updateWithTheme()
        
    }
    
    //MARK: Language
    
    @objc func didChangedLanguage(_ notification: Notification? = nil) {
        self.loadingStubForSelected.title = "DownloadingRoutesStatus".localized()
        self.emptyStubForSelected.subviews.forEach { (subview) in
            if let button = subview as? UIButton {
                button.setTitle("DragTitle".localized(), for: .normal)
            }
        }
        if self.isExpanded {
            DispatchQueue.main.async {
                self.collectionViewForAll.reloadData()
            }
        }
    }
    
    //MARK: Theme
    
    @objc func didChangedTheme(_ notification: Notification? = nil) {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.1, animations: { [weak self] in
                self?.updateWithTheme()
                }, completion: { (finished) in
            })
        }
    }
    
    func updateWithTheme() {
        self.setNeedsStatusBarAppearanceUpdate()
        self.headerView.backgroundColor = Settings.shared.theme.navigationBarBackgroudColor
        self.collectionViewForAll.backgroundColor = Settings.shared.theme.navigationBarBackgroudColor
        self.collectionViewForAll.indicatorStyle = Settings.shared.theme == .light ? .black : .white
        
        self.loadingStubForSelected.titleLabel.textColor = Settings.shared.theme.textColor
        self.loadingStubForSelected.activityIndicatorView.color = Settings.shared.theme.textColor
        
        self.emptyStubForSelected.setTitleColor(Settings.shared.theme.textColor, for: .normal)
        
        if let button = self.collectionViewForSelected.backgroundView?.subviews.first as? UIButton {
            button.setTitleColor(Settings.shared.theme.textColor, for: .normal)
        }
        self.backgroundView.backgroundColor = Settings.shared.theme.navigationBarBackgroudColor
        self.draggableView.visibleHolder.backgroundColor = Settings.shared.theme.navigationBarBackgroudColor
        self.draggableView.shadowView.backgroundColor = Settings.shared.theme.navigationBarShadowColor
        self.draggableView.dragIndicatorView.backgroundColor = Settings.shared.theme.secondaryTextColor
        self.collectionViewForAll.reloadData()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Settings.shared.theme.statusBarStyle
    }
    
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .fade
    }
    
    //MARK: - actions
    
    @objc func handleTapOnDragIndicator(_ recognizer: UITapGestureRecognizer) {
        if self.isExpanded {
            self.collapse()
            self.isExpanded = false
        } else {
            self.expand()
            self.isExpanded = true
        }
    }
    
    @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
        if isExpanded && recognizer == self.panHeaderView {
            return
        }
        if !isExpanded && recognizer == self.panCollectionView {
            return
        }
        
        let translate = recognizer.translation(in: self.view)
        proccedTranslation(recognizer: recognizer, translate)
        recognizer.setTranslation(.zero, in: self.draggableView)
    }
    
    func proccedTranslation(recognizer: UIPanGestureRecognizer, _ translate: CGPoint) {
        switch recognizer.state {
        case .began:
            if !self.isExpanded && self.collectionViewForAll.contentOffset.y != 0 {
                UIView.animate(withDuration: 0.01) {
                    self.collectionViewForAll.setContentOffset(.zero, animated: true)
                }
            }
        case .changed:
            var newHeight = self.view.frame.height + translate.y
            newHeight = max(min(newHeight, self.maxExpandedHeight), self.collapsedHeight)
            self.view.snp.updateConstraints { (make) in
                make.height.equalTo(newHeight)
            }
        case .ended:
            let currentVisibleBody = self.view.frame.height - self.collapsedHeight
            let halfCollectionViewSize = self.collectionViewForAll.contentSize.height / 2
            
            let velocity = recognizer.velocity(in: self.view)
            if currentVisibleBody > halfCollectionViewSize {
                if velocity.y < -800 {
                    self.collapse()
                    self.isExpanded = false
                } else {
                    self.expand(scrollToTop: false)
                    self.isExpanded = true
                }
            } else {
                if velocity.y > 1300 {
                    self.expand(scrollToTop: false)
                    self.isExpanded = true
                } else {
                    self.collapse()
                    self.isExpanded = false
                }
            }
        default:
            break
        }
    }
        
    @objc func handleTapAddSelectedCell(_ sender: Any) {
        if !self.isExpanded {
            self.expand()
        }
    }
    
    //MARK: - private
    
    func collapse() {
        self.view.snp.updateConstraints { (make) in
            make.height.equalTo(self.collapsedHeight)
        }
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: [.curveEaseOut], animations: {
            if self.collectionViewForAll.contentOffset.y != 0 {
                self.collectionViewForAll.setContentOffset(.zero, animated: false)
            }
            self.view.layoutSubviews()
        }, completion: { (finished) in
            self.isExpanded = false
            self.delegate?.didChangeState(self, expanded: self.isExpanded)
            self.collectionViewForAll.reloadData()
        })
        return
    }
    
    func expand(scrollToTop: Bool = true) {
        self.view.snp.updateConstraints { (make) in
            make.height.equalTo(self.maxExpandedHeight)
        }
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0, options: [.curveEaseOut], animations: {
            if self.collectionViewForAll.contentOffset.y != 0 && scrollToTop {
                self.collectionViewForAll.setContentOffset(.zero, animated: false)
            }
            self.view.layoutSubviews()
        }, completion: { (finished) in
            self.isExpanded = true
            self.delegate?.didChangeState(self, expanded: self.isExpanded)
            self.collectionViewForAll.reloadData()
        })
        return
    }
    
    private func mutateToDictionary(routes: [Route]) -> [Route.Kind: [Route]] {
        var dict = [Route.Kind: [Route]]()
        for route in routes {
            if dict[route.kind] == nil {
                dict[route.kind] = [route]
            } else {
                dict[route.kind]?.append(route)
            }
        }
        return dict
    }
    
    //MARK: - public
    
    func showLoading() {
        if self.selectedRoutesIds.count == 0 {
            DispatchQueue.main.async {
                self.collectionViewForSelected.backgroundView = self.loadingStubForSelected
                self.loadingStubForSelected.title = "DownloadingRoutesStatus".localized()
                self.loadingStubForSelected.activityIndicatorView.startAnimating()
            }
        }
    }
    
    func showError() {
        if self.selectedRoutesIds.count == 0 {
            DispatchQueue.main.async {
                self.collectionViewForSelected.backgroundView = self.loadingStubForSelected
                self.loadingStubForSelected.title  = "FailedDownloadRoutesStatus".localized()
                self.loadingStubForSelected.activityIndicatorView.stopAnimating()
            }
        }
    }
    
    func update(with routes: [Route]) {
        self.allRoutes = mutateToDictionary(routes: routes)
    }
    
    func select(route: Route) {
        impact.impactOccurred()
        if self.selectedRoutes.contains(route) { return }
        
        if self.selectedRoutes.count == Constants.maximumNumberOfSelectedRoutes {
            if let routeToDelete = self.selectedRoutes.first {
                self.deselect(route: routeToDelete)
            }
        }
        
        if let color = RoutesColorManager.default.randomColorFromAvailable() {
            self.colorForRouteId[route.id] = color
        }
        
        self.selectedRoutes.append(route)
        if self.selectedRoutesIds.count > 0 {
            self.collectionViewForSelected.backgroundView = nil
        }
        
        let sectionInAll = self.allRoutesKeysSorted.firstIndex(of: route.kind) ?? 0
        let itemInAll = self.allRoutes[route.kind]?.firstIndex(of: route) ?? 0
        let indexPathInAll = IndexPath(item: itemInAll, section: sectionInAll)
        
        let indexPathInSelected = IndexPath(item: self.selectedRoutes.count - 1, section: 0)
                
        self.delegate?.willSelectTransport(with: route.id)
        
        guard viewIfLoaded?.window != nil else {
            return
        }
        
        self.collectionViewForSelected.performBatchUpdates({
            self.collectionViewForSelected.insertItems(at: [indexPathInSelected])
        }) { (finished) in
            self.delegate?.didSelectTransport(with: route.id)
        }
        
        self.collectionViewForAll.performBatchUpdates({
            self.collectionViewForAll.reloadItems(at: [indexPathInAll])
        }) { (finished) in
        }
        
    }
    
    func deselect(route: Route) {
        impact.impactOccurred()
        guard let indexToRemove = self.selectedRoutes.firstIndex(of: route) else { return }
        self.selectedRoutes.remove(at: indexToRemove)
        
        if let color = self.colorForRouteId[route.id] {
            RoutesColorManager.default.returnColorToAvailable(color)
            self.colorForRouteId.removeValue(forKey: route.id)
        }
        
        let sectionInAll = self.allRoutesKeysSorted.firstIndex(of: route.kind) ?? 0
        let itemInAll = self.allRoutes[route.kind]?.firstIndex(of: route) ?? 0
        let indexPathInAll = IndexPath(item: itemInAll, section: sectionInAll)
        
        let indexPathInSelected = IndexPath(item: indexToRemove, section: 0)
        
        if self.selectedRoutesIds.count == 0 {
            self.collectionViewForSelected.backgroundView = self.emptyStubForSelected
        }
        
        self.delegate?.willDeselectTransport(with: route.id)
        
        guard viewIfLoaded?.window != nil else { return }
        
        self.collectionViewForSelected.performBatchUpdates({
            self.collectionViewForSelected.deleteItems(at: [indexPathInSelected])
        }) { (finished) in
            self.delegate?.didDeselectTransport(with: route.id)
        }
        
        self.collectionViewForAll.performBatchUpdates({
            self.collectionViewForAll.reloadItems(at: [indexPathInAll])
        }) { (finished) in
        }
        
    }
    
}


extension SelectTransportController: UICollectionViewDataSource {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        if collectionView.tag == self.selectedCollectionViewTag {
            return 1
        } else if collectionView.tag == self.allCollectionViewTag {
            return self.allRoutesKeysSorted.count
        }
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView.tag == self.selectedCollectionViewTag {
            return self.selectedRoutes.count
        } else if collectionView.tag == self.allCollectionViewTag {
            return self.allRoutes[self.allRoutesKeysSorted[section]]?.count ?? 0
        }
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TransportCell.identifier, for: indexPath) as! TransportCell
        if collectionView.tag == self.selectedCollectionViewTag {
            let route = self.selectedRoutes[indexPath.item]
            cell.text = route.name
            var color = Settings.shared.theme.routeCellBackgroundColor
            if let routeColor = self.colorForRouteId[route.id] {
                color = routeColor
            }
            cell.contentView.backgroundColor = color
        } else if collectionView.tag == self.allCollectionViewTag {
            let route = self.allRoutes[self.allRoutesKeysSorted[indexPath.section]]![indexPath.row]
            cell.text = route.name
            if self.selectedRoutes.contains(route), let color = self.colorForRouteId[route.id] {
                cell.contentView.backgroundColor = color
            } else {
                cell.contentView.backgroundColor = Settings.shared.theme.routeCellBackgroundColor
                if #available(iOS 13, *), Settings.shared.theme == .system {
                    cell.label.textColor = UIColor.label
                }
            }
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        if collectionView.tag == self.allCollectionViewTag {
            return CGSize(width: self.view.frame.width, height: self.headerHeight * 0.8)
        }
        return .zero
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        switch kind {
        case UICollectionView.elementKindSectionHeader:

            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind,
                                                                             withReuseIdentifier: TransportHeader.identifier,
                                                                             for: indexPath) as! TransportHeader
            var title: String = ""
            if collectionView.tag == self.allCollectionViewTag {
                let kind = self.allRoutesKeysSorted[indexPath.section]
                title = kind.name
                headerView.titleLabel.font = Font.Avenir.semibold.withSize(14)
            }
            headerView.title = title
            return headerView
        default:
            fatalError("supplementary view was not implemented")
        }
    }
    
    //MARK: - scroll delegation
    
    var isScrolledToBottom: Bool {
        let contentOffsetY = self.collectionViewForAll.contentOffset.y.rounded(.down)
        let differenceBetweenSize = self.collectionViewForAll.contentSize.height.rounded(.down) - self.collectionViewForAll.frame.size.height.rounded(.down)
        if (contentOffsetY >= differenceBetweenSize) {
            return true
        } else {
            return false
        }
    }

}


extension SelectTransportController: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView.tag == self.selectedCollectionViewTag {
            
            let route = self.selectedRoutes[indexPath.row]
            self.deselect(route: route)
            
        } else if collectionView.tag == self.allCollectionViewTag {
            
            let route = self.allRoutes[self.allRoutesKeysSorted[indexPath.section]]![indexPath.row]
            let isSelected = self.selectedRoutes.contains(route)
            if isSelected {
                self.deselect(route: route)
            } else {
                self.select(route: route)
            }

        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if collectionView.tag == self.selectedCollectionViewTag {
            return cellSizeForSelectedCV
        } else if collectionView.tag == self.allCollectionViewTag {
            return cellSizeForAllCV
        }
        return .zero
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        if collectionView.tag == self.selectedCollectionViewTag {
            return sectionInsetsForSelectedCV
        } else if collectionView.tag == self.allCollectionViewTag {
            return sectionInsetsForAllCV
        }
        return .zero
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView.tag == self.selectedCollectionViewTag {
            return self.interitemSpace
        } else if collectionView.tag == self.allCollectionViewTag {
            return self.interitemSpaceForCVAll
        }
        return 0
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        if collectionView.tag == self.selectedCollectionViewTag {
            return self.interitemSpace
        } else if collectionView.tag == self.allCollectionViewTag {
            return self.interitemSpaceForCVAll
        }
        return 0
    }
    
}


extension SelectTransportController: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer == self.panCollectionView {
            return self.isScrolledToBottom
        } else {
            return true
        }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if (otherGestureRecognizer.view as? UIScrollView) != nil {
            if self.collectionViewForAll.contentSize.height.rounded(.up) == self.collectionViewForAll.frame.height.rounded(.up) {
                return false
            } else {
                let translation = (gestureRecognizer as? UIPanGestureRecognizer)?.translation(in: self.view).y ?? 0
                if translation < 0 {
                    self.collectionViewForAll.panGestureRecognizer.isEnabled.toggle()
                    self.collectionViewForAll.panGestureRecognizer.isEnabled.toggle()
                    return isScrolledToBottom
                } else {
                    return true
                }
            }
        }
        return false
    }
    
}
