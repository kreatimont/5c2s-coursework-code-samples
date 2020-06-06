//
//  LvivGTFSTransportDataProvider.swift
//  CityTransportGuide
//
//  Created by Alexandr Nadtoka on 12/25/18.
//  Copyright © 2018 kreatimont. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift
import Localize_Swift

class LvivGTFSTransportDataProvider: TransportDataProvider {
    
    var city: City
    var routes: [Route]
    var stops: Set<Stop>
    
    var oblastRoutesNames: [String] = ["184А", "156", "184", "1001", "799", "816", "131", "217А"]
    
    private var gtfsStops: [GTFSStop]
    private let networkManager = NetworkManager()
    private let queue = DispatchQueue(label: "lviv-provider-queue", qos: .userInitiated, attributes: .concurrent)
    
    init(city: City) {
        self.city = city
        self.routes = []
        self.stops = []
        self.gtfsStops = []
    }
    
    deinit {
        DDLogInfo("LvivTransportDataProvider \(city.name.uppercased()) - deinited")
    }
    
    var forceUseNetwork: Bool = false
    
    func updateDatabase(completion: ((Bool, String?) -> ())?) {
        self.forceUseNetwork = true
        self.provideRoutes { (result, _) in
            self.forceUseNetwork = false
            switch result {
            case .success:
                completion?(true, nil)
            case .failure(let error):
                completion?(false, error.localizedDescription)
            }
        }
    }
    
    //MARK: - routes
    
    func provideRoutes(completion: RouteCompletion?) {
        if Settings.shared.neeedToUpdateDatabase || self.forceUseNetwork {
            if Settings.shared.neeedToUpdateDatabase {
                self.forceUseNetwork = true
            }
            self.downloadGTFSStatic(completion: completion)
        } else {
            CoreDataManager.shared.getAllRoutes(for: self.city) { [weak self] (coreDataRoutes) in
                guard let self = self else { return }
                if coreDataRoutes.count > 0 && !self.forceUseNetwork {
                    self.routes = coreDataRoutes
                    completion?(.success(coreDataRoutes), false)
                } else {
                    self.downloadGTFSStatic(completion: completion)
                }
            }
        }
    }
    
    private func downloadGTFSStatic(completion: RouteCompletion?) {
        var task = DownloadService.shared.download(request: Router<LvivGPSApi>().asUrlRequest(from: .static)!)
        task.completionHandler = { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let data):
                self.queue.async {
                    switch GTFSParser.shared.parseGTFSStatic(staticArchive: data) {
                    case .success(let staticData):
                        let gtfsRoutes = staticData.routes
                        let gtfsStops = staticData.stops
                        let gtfsTrips = staticData.trips
                        let gtfsShapes = staticData.shapes
                        
                        var commonRoutes = [Route]()
                        
                        for route in gtfsRoutes {
                            
                            var lines = [RouteLine]()
                            
                            let trips = gtfsTrips.filter({ $0.routeId == route.id })
                            let shapeIds = Set(trips.map({ $0.shapeId }))
                            
                            for shapeId in shapeIds {
                                let points = gtfsShapes.filter({ $0.id == shapeId }).sorted(by: { $0.sequenceNumber < $1.sequenceNumber }).map({ $0.location })
                                lines.append(RouteLine(with: points))
                            }
                            
                            
                            let nameNumberSubstring = route.name.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                            guard let digitsRange = route.name.range(of: nameNumberSubstring) else {
                                continue
                            }
                            var number: String
                            if let numberInt = Int(nameNumberSubstring) {
                                number = "\(numberInt)"
                            } else {
                                number = nameNumberSubstring
                            }
                            
                            let prefix = route.name.prefix(upTo: digitsRange.lowerBound)
                            var kind: Route.Kind
                            if prefix == "А" {
                                kind = .bus
                            } else if prefix == "Тр" {
                                kind = .trolleybus
                            } else if prefix == "Т" {
                                kind = .tram
                            } else if prefix == "Н-А" {
                                kind = .nightRoute
                                number = "Н\(number)"
                            } else {
                                kind = .bus
                            }
                            
                            commonRoutes.append(Route(id: route.id, name: number, fullName: route.fullName, kind: kind, lines: lines))
                            
                        }
                        
                        let commonStops = gtfsStops.map({ (gtfsStop) -> Stop in
                            return Stop(id: gtfsStop.id, name: gtfsStop.name, location: gtfsStop.location)
                        })
                        self.stops = Set(commonStops)
                        self.gtfsStops = gtfsStops
                        
                        self.downloadAndMergeOblastRoutes { [weak self] (oblastRoutes) in
                            guard let self = self else { return }
                            commonRoutes.append(contentsOf: oblastRoutes)
                            
                            self.routes = commonRoutes.sorted(by: { obj1, obj2 in
                                if let int1 = Int(obj1.name), let int2 = Int(obj2.name) {
                                    return int1 < int2
                                } else {
                                    return obj1.name < obj2.name
                                }
                            })
                            
                            CoreDataManager.shared.removeAllGTFSStops(for: self.city) { [weak self] (f1) in
                                guard let self = self else { return }
                                CoreDataManager.shared.removeAllRoutes(for: self.city) { [weak self] (f2) in
                                    guard let self = self else { return }
                                    CoreDataManager.shared.save(routes: self.routes, for: self.city) { [weak self] (f3) in
                                        guard let self = self else { return }
                                        CoreDataManager.shared.saveGTFSStops(stops: self.gtfsStops, for: self.city) { [weak self] (f4) in
                                            guard let self = self else { return }
                                            
                                            DispatchQueue.main.async {
                                                completion?(.success(self.routes), true)
                                            }
                                            
                                        }
                                    }
                                }
                            }
                            
                        }
                        
                    case .failure(_):
                        completion?(.failure(createError(with: "CantParseGTFS".localized())), false)
                        
                    }
                }
            case .failure(let error):
                completion?(.failure(error), false)
            }
        }
        task.resume()
        
    }
    
    private func downloadAndMergeOblastRoutes(completion: @escaping ([Route]) -> ()) {
        self.networkManager.getLvivOblastRoutes { [weak self] (lodaRoutes, error) in
            guard let self = self else { return }
            guard let safeLodaRoute = lodaRoutes else {
                completion([])
                return
            }
            
            var lodaRoutesMutable = safeLodaRoute.filter({ self.oblastRoutesNames.contains($0.name) })
            let linesDownloadGroup = DispatchGroup()
            
            for (index, sRoute) in lodaRoutesMutable.enumerated() {
                linesDownloadGroup.enter()
                if !Thread.isMainThread {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                self.networkManager.getLvivOblastRoutePath(for: sRoute.id, completion: { (lines, error) in
                    if let sLines = lines {
                        lodaRoutesMutable[index].lines = [sLines]
                    }
                    linesDownloadGroup.leave()
                })
            }
            linesDownloadGroup.notify(queue: self.queue, work: DispatchWorkItem(block: { [weak self] in
                guard let _ = self else { return }
                var commonRoutes = lodaRoutesMutable.map({ Route(id: $0.id, name: $0.name, fullName: $0.fullName, kind: $0.kind, lines: $0.lines) })
                commonRoutes.sort(by: { (first, second) -> Bool in
                    let nameNumberSubstring1 = first.name.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                    let nameNumberSubstring2 = second.name.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                    return (Int(nameNumberSubstring1)) ?? 0 < (Int(nameNumberSubstring2) ?? 0)
                })
                completion(commonRoutes)
            }))
        }
    }
    
    func provideRouteSync(routeId: Int) -> Route? {
        if self.routes.count > 0 {
            return self.routes.object(id: routeId)
        } else {
            return CoreDataManager.shared.getRouteSync(with: routeId, and: self.city)
        }
    }
    
    func provideRoutes(with ids: [Int], completion: ResultType<[Route]>.Completion?) {
        if self.routes.count > 0 {
            queue.async {
                let filtered = self.routes.filter({ ids.contains($0.id) })
                completion?(.success(filtered))
            }
        } else {
            self.provideRoutes { [weak self] (result, _) in
                guard let _ = self else { return }
                switch result {
                case .success(let routes):
                    let filtered = routes.filter({ ids.contains($0.id) })
                    completion?(.success(filtered))
                case .failure(let error):
                    completion?(.failure(error))
                }
            }
        }
    }
    
    //MARK: - stops
    
    func provideStops(completion: ResultType<Set<Stop>>.Completion?) {
        if self.stops.count > 0 {
            completion?(.success(self.stops))
        } else {
            CoreDataManager.shared.getAllGTFSStops(for: self.city) { [weak self] (gtfsStops) in
                guard let self = self else { return }
                if gtfsStops.count > 0 {
                    self.gtfsStops = gtfsStops
                    let commonStops = gtfsStops.map({ (gtfsStop) -> Stop in
                        return Stop(id: gtfsStop.id, name: gtfsStop.name, location: gtfsStop.location)
                    })
                    self.stops = Set(commonStops)
                    completion?(.success(self.stops))
                } else {
                    self.provideRoutes(completion: { [weak self] (result, _) in
                        guard let self = self else { return }
                        completion?(.success(self.stops))
                    })
                }
            }
        }
    }
    
    //MARK: - real-time
    
    func provideRealTimePositions(routeIds: [Int], completion: ResultType<[Int: [Transport]]>.Completion?) {
        var oblastRoutes = [Route]()
        routeIds.compactMap({ self.provideRouteSync(routeId: $0) }).forEach({ r in
            if self.oblastRoutesNames.contains(r.name) {
                oblastRoutes.append(r)
            }
        })
        
        var result = [Int: [Transport]]()
        
        let transportGroup = DispatchGroup()
        
        for oblastRoute in oblastRoutes {
            transportGroup.enter()
            self.networkManager.getLvivOblastTransport(for: oblastRoute.id) { (transport, error) in
                if let t = transport {
                    result[oblastRoute.id] = t
                }
                transportGroup.leave()
            }
        }
        
        transportGroup.notify(queue: self.queue, work: DispatchWorkItem(block: { [weak self] in
            guard let self = self else { return }
            self.networkManager.getLvivTransportRealTime { [weak self] (realTimeTransport: [GTFSTransport]?, error) in
                guard let self = self else { return }
                guard let transports = realTimeTransport else {
                    completion?(.failure(createError(with: error ?? "")))
                    return
                }
                for gtfsTransport in transports {
                    if let id = Int(gtfsTransport.id), let sRouteId = gtfsTransport.routeId, let routeIdInt = Int(sRouteId), routeIds.contains(routeIdInt) {
                        let transport = Transport(id: id, location: gtfsTransport.location, azimut: Int(gtfsTransport.bearing), vehicleNumber: gtfsTransport.vehicleNumber, routeId: Int(gtfsTransport.routeId ?? ""), routeName: self.provideRouteSync(routeId: routeIdInt)?.name)
                        
                        if result[routeIdInt] != nil {
                            result[routeIdInt]?.append(transport)
                        } else {
                            result[routeIdInt] = [transport]
                        }
                        
                    }
                    
                }
                
                completion?(.success(result))
            }
            
        }))
        
    }
    
    //MARK: - arrivals
    
    func provideArrivals(stop: Stop, completion: ResultType<[Arrival]>.Completion?) {
        
        guard let gtfsStop = self.gtfsStops.first(where: { $0.id == stop.id }) else {
            completion?(.failure(createError(with: "StopNotFound".localized())))
            return
        }
        
        guard let codeRaw = gtfsStop.code,
            let code = codeRaw.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else {
                completion?(.failure(createError(with: "StopWithoutCode".localized())))
                return
        }
        
        self.networkManager.getLvivArrivals(stopCode: code) { [weak self] (ladArrivals, error) in
            guard let self = self else { return }
            
            guard let sLadArrivals = ladArrivals else {
                completion?(.failure(createError(with: error ?? "")))
                return
            }
            
            var newArrivals = [Arrival]()
            for ladArrival in sLadArrivals {
                guard let timeLeft = Int(ladArrival.timeLeft.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) else {
                    continue
                }
                
                var typePrefix: String
                
                if ladArrival.routeType == .bus || ladArrival.routeType == .suburbanBus || ladArrival.routeType == .villageBus {
                    typePrefix = "A"
                } else {
                    typePrefix = "T"
                }
                
                guard let route = self.routes.first(where: { (route) -> Bool in
                    return "\(typePrefix)\(route.name)".lowercased() == ladArrival.routeName.lowercased() && route.kind == ladArrival.routeType
                }) else {
                    continue
                }
                
                newArrivals.append(Arrival(routeId: route.id, transportId: -1, time: timeLeft))
            }
            
            completion?(.success(newArrivals))
            
        }
        
    }
    
}

