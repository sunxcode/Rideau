//
//  SnapPoint.swift
//  Cabinet
//
//  Created by muukii on 2019/02/05.
//  Copyright © 2019 muukii. All rights reserved.
//

import Foundation

public enum CabinetSnapPoint : Hashable {
  
  case fraction(CGFloat)
  case pointsFromTop(CGFloat)
  case pointsFromBottom(CGFloat)
  
  public static let hidden: CabinetSnapPoint = .fraction(-0.1)
  public static let full: CabinetSnapPoint = .fraction(1)
}

struct ResolvedSnapPoint : Hashable, Comparable {
  static func < (lhs: ResolvedSnapPoint, rhs: ResolvedSnapPoint) -> Bool {
    return lhs.pointsFromTop < rhs.pointsFromTop
  }
  
  let pointsFromTop: CGFloat
  
  let source: CabinetSnapPoint
  
  init(_ pointsFromSafeAreaTop: CGFloat, source: CabinetSnapPoint) {
    self.pointsFromTop = pointsFromSafeAreaTop
    self.source = source
  }
}

struct ResolvedSnapPointRange : Hashable {
  
  let start: ResolvedSnapPoint
  let end: ResolvedSnapPoint
  
  init(_ a: ResolvedSnapPoint, b: ResolvedSnapPoint) {
    
    if a < b {
      self.start = a
      self.end = b
    } else {
      self.start = b
      self.end = a
    }
    
  }
  
  func pointCloser(by point: CGFloat) -> ResolvedSnapPoint? {
    
    if ClosedRange.init(uncheckedBounds: (start.pointsFromTop, end.pointsFromTop)).contains(point) {
      
      let first = abs(point - start.pointsFromTop)
      let second = abs(end.pointsFromTop - point)
      
      if first > second {
        return end
      } else {
        return start
      }
      
    } else {
      return nil
    }
  }
  
}

//struct AbsoluteSnapPointRangeStore<T> {
//  
//  private var backingStore: [AbsoluteSnapPointRange : T] = [:]
//  
//  init() {
//    
//  }
//  
//  subscript (_ range: AbsoluteSnapPointRange) -> T? {
//    return backingStore
//  }
//  
//}