//
//  TransportDataProvider.swift
//  CityTransportGuide
//
//  Created by Alexandr Nadtoka on 12/25/18.
//  Copyright © 2018 kreatimont. All rights reserved.
//

import Foundation

typealias RouteCompletion = ((ResultType<[Route]>, Bool) -> ())

protocol TransportDataProvider {
 
    var city: City { get }
    var routes: [Route] { get }
    var stops: Set<Stop> { get }
    
    var forceUseNetwork: Bool { get set }
    
    func updateDatabase(completion: ((Bool, String?) -> ())?)
    
    func provideRoutes(completion: RouteCompletion?)
    func provideRouteSync(routeId: Int) -> Route?
    func provideRoutes(with ids: [Int], completion: ResultType<[Route]>.Completion?)
    
    func provideStops(completion: ResultType<Set<Stop>>.Completion?)
    
    func provideRealTimePositions(routeIds: [Int], completion: ResultType<[Int: [Transport]]>.Completion?)
    
    func provideArrivals(stop: Stop, completion: ResultType<[Arrival]>.Completion?)
    
}

protocol WebSocketTransportDataProvider: TransportDataProvider {
    var activeRoutes: [Int] { get set }
    var delegate: WebSocketTransportDataProviderDelegate? { get set }
    
    func startObserving(activeRoutes: [Int]?)
    func stopObserving(clearActiveRoutes: Bool)
    
    func provideRouteInfo(routeId: Int, completion: ResultType<Route>.Completion?)
}

protocol WebSocketTransportDataProviderDelegate: class {
    func updateTransportPositions(transports: [Int: [Transport]])
}
