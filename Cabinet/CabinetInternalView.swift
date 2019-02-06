//
//  CabinetInternalView.swift
//  Cabinet
//
//  Created by muukii on 2019/02/07.
//  Copyright © 2019 muukii. All rights reserved.
//

import UIKit

final class CabinetInternalView : TouchThroughView {
  
  // Needs for internal usage
  internal var didChangeSnapPoint: (CabinetSnapPoint) -> Void = { _ in }
  
  private var topConstraint: NSLayoutConstraint!
  
  private var bottomConstraint: NSLayoutConstraint!
  
  private let backdropView = TouchThroughView()
  
  public let containerView = CabinetContainerView()
  
  public let configuration: CabinetView.Configuration
  
  private var resolvedConfiguration: ResolvedConfiguration = .init()
  
  private var containerDraggingAnimator: UIViewPropertyAnimator?
  
  private var dimmingAnimator: UIViewPropertyAnimator?
  
  private var animatorStore: AnimatorStore = .init()
  
  private var sizeThatLastUpdated: CGSize?
  
  private var currentSnapPoint: ResolvedSnapPoint?
  
  private var topMarginLayoutGuide: UILayoutGuide!
  
  private var originalTranslateYForOut: CGFloat?
  
  init(
    frame: CGRect,
    configuration: CabinetView.Configuration?
    ) {
    self.configuration = configuration ?? .init()
    super.init(frame: .zero)
    
  }
  
  func setup(topMarginLayoutGuide: UILayoutGuide) {
    
    self.topMarginLayoutGuide = topMarginLayoutGuide
    
    containerView.translatesAutoresizingMaskIntoConstraints = false
    
    addSubview(backdropView)
    backdropView.frame = bounds
    backdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    
    addSubview(containerView)
    containerView.set(owner: self)
    
    topConstraint = containerView.topAnchor.constraint(equalTo: topMarginLayoutGuide.bottomAnchor, constant: 0)
    
    bottomConstraint = containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 0)
    
    NSLayoutConstraint.activate([
      topConstraint,
      bottomConstraint,
      containerView.rightAnchor.constraint(equalTo: rightAnchor, constant: 0),
      containerView.leftAnchor.constraint(equalTo: leftAnchor, constant: 0),
      ])
    
    gesture: do {
      
      let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
      containerView.addGestureRecognizer(pan)
    }
    
  }
  
  @available(*, unavailable)
  required init?(coder aDecoder: NSCoder) {
    fatalError()
  }
  
  func set(snapPoint: CabinetSnapPoint, animated: Bool, completion: @escaping () -> Void) {
    
    preventCurrentAnimations: do {
      
      animatorStore.allAnimators().forEach {
        $0.stopAnimation(true)
      }
      
      animatorStore.removeAllAnimations()
      
      containerDraggingAnimator?.stopAnimation(true)
    }
    
    guard let target = resolvedConfiguration.snapPoints.first(where: { $0.source == snapPoint }) else {
      assertionFailure("Not found such as snappoint")
      return
    }
    
    if animated {
      continueInteractiveTransition(target: target, velocity: .zero, completion: completion)
    } else {
      UIView.performWithoutAnimation {
        continueInteractiveTransition(target: target, velocity: .zero, completion: completion)
      }
    }
    
  }
  
  @objc private func handlePan(gesture: UIPanGestureRecognizer) {
    
    let translation = gesture.translation(in: gesture.view!)
    
    let offset = topMarginLayoutGuide.layoutFrame.height
    
    var nextValue: CGFloat
    if let v = containerView.layer.presentation().map({ $0.frame.origin.y }) {
      nextValue = v
    } else {
      nextValue = containerView.frame.origin.y
    }
    
    nextValue += translation.y
    nextValue.round()
    
    
    let currentLocation = resolvedConfiguration.currentLocation(from: nextValue - offset)
    
    switch gesture.state {
    case .began:
      startInteractiveTransition()
      fallthrough
    case .changed:
      
      switch currentLocation {
      case .exact:
        
        originalTranslateYForOut = nil
        containerView.frame.origin.y = nextValue
        
      case .between(let range):
        originalTranslateYForOut = nil
        
        let fractionCompleteInRange = CalcBox.init(topConstraint.constant)
          .progress(
            start: range.start.pointsFromTop,
            end: range.end.pointsFromTop
          )
          .clip(min: 0, max: 1)
          .value
          .fractionCompleted
        
        containerView.frame.origin.y = nextValue
        
        animatorStore[range]?.forEach {
          $0.isReversed = false
          $0.pauseAnimation()
          $0.fractionComplete = fractionCompleteInRange
        }
        
        animatorStore.animators(after: range).forEach {
          $0.isReversed = false
          $0.pauseAnimation()
          $0.fractionComplete = 0
        }
        
        animatorStore.animators(before: range).forEach {
          $0.isReversed = false
          $0.pauseAnimation()
          $0.fractionComplete = 1
        }
        
      case .outOf(let point):
        
        let offset = translation.y * 0.1
        topConstraint.constant += offset
        bottomConstraint.constant = 0
      }
      
    case .ended, .cancelled, .failed:
      
      let vy = gesture.velocity(in: gesture.view!).y
      
      let target: ResolvedSnapPoint = {
        switch currentLocation {
        case .between(let range):
          
          guard let pointCloser = range.pointCloser(by: nextValue - offset) else {
            fatalError()
          }
          
          switch vy {
          case -20...20:
            return pointCloser
          case ...(-20):
            return range.start
          case 20...:
            return range.end
          default:
            fatalError()
          }
          
        case .exact(let point):
          return point
          
        case .outOf(let point):
          return point
        }
      }()
      
      let targetTranslateY = target.pointsFromTop
      
      func makeVelocity() -> CGVector {
        
        let base = CGVector(
          dx: 0,
          dy: targetTranslateY - nextValue
        )
        
        var initialVelocity = CGVector(
          dx: 0,
          dy: min(abs(vy / base.dy), 30)
        )
        
        if initialVelocity.dy.isInfinite || initialVelocity.dy.isNaN {
          initialVelocity.dy = 0
        }
        
        if case .outOf = currentLocation {
          return .zero
        }
        
        return initialVelocity
      }
      
      continueInteractiveTransition(target: target, velocity: makeVelocity(), completion: {})
    default:
      break
    }
    
    gesture.setTranslation(.zero, in: gesture.view!)
    
  }
  
  private func startInteractiveTransition() {
    
    containerDraggingAnimator?.pauseAnimation()
    containerDraggingAnimator?.stopAnimation(true)
    
    animatorStore.allAnimators().forEach {
      $0.pauseAnimation()
    }
    
  }
  
  override func layoutSubviews() {
    
    func _setup() {
      
      let offset: CGFloat = 0
      
      let maxHeight = self.bounds.height - topMarginLayoutGuide.layoutFrame.height
      
      let points = configuration.snapPoints.map { snapPoint -> ResolvedSnapPoint in
        switch snapPoint {
        case .fraction(let fraction):
          let value = round(maxHeight - maxHeight * fraction)
          return .init(value, source: snapPoint)
        case .pointsFromTop(let points):
          return .init(max(maxHeight, points + offset), source: snapPoint)
        case .pointsFromBottom(let points):
          return .init(min(maxHeight, maxHeight - points), source: snapPoint)
        }
      }
      
      resolvedConfiguration.set(snapPoints: points)
    }
    
    if sizeThatLastUpdated == nil {
      super.layoutSubviews()
      sizeThatLastUpdated = bounds.size
      _setup()
      
      if let initial = resolvedConfiguration.snapPoints.last {
        set(snapPoint: initial.source, animated: false, completion: {})
      }
      
      return
    }
    
    super.layoutSubviews()
    
    guard sizeThatLastUpdated != bounds.size else {
      return
    }
    
    sizeThatLastUpdated = bounds.size
    
    _setup()
    
    set(snapPoint: currentSnapPoint!.source, animated: true, completion: {})
    
  }
  
  private func continueInteractiveTransition(
    target: ResolvedSnapPoint,
    velocity: CGVector,
    completion: @escaping () -> Void
    ) {
    
    currentSnapPoint = target
    
    let animator = UIViewPropertyAnimator.init(
      duration: 0.4,
      timingParameters: UISpringTimingParameters(
        mass: 5,
        stiffness: 1300,
        damping: 300, initialVelocity: velocity
      )
    )
    
    // flush pending updates
    
    self.layoutIfNeeded()
    
    animator
      .addAnimations {
        self.topConstraint.constant = target.pointsFromTop
        self.bottomConstraint.constant = target.pointsFromTop
        self.setNeedsLayout()
        self.layoutIfNeeded()
    }
    
    animator.addCompletion { _ in
      completion()
      self.didChangeSnapPoint(target.source)
    }
    
    animator.isInterruptible = true
    
    animator.startAnimation()
    
    containerDraggingAnimator = animator
    
  }
  
}

extension CabinetInternalView {
  
  private struct AnimatorStore {
    
    private var backingStore: [ResolvedSnapPointRange : [UIViewPropertyAnimator]] = [:]
    
    subscript (_ range: ResolvedSnapPointRange) -> [UIViewPropertyAnimator]? {
      get {
        return backingStore[range]
      }
      set {
        backingStore[range] = newValue
      }
    }
    
    mutating func set(animator: UIViewPropertyAnimator, for key: ResolvedSnapPointRange) {
      
      var array = self[key]
      
      if array != nil {
        array?.append(animator)
        self[key] = array
      } else {
        let array = [animator]
        self[key] = array
      }
      
    }
    
    func animators(after: ResolvedSnapPointRange) -> [UIViewPropertyAnimator] {
      
      return backingStore
        .filter { $0.key.end < after.start }
        .reduce(into: [UIViewPropertyAnimator]()) { (result, args) in
          result += args.value
      }
      
    }
    
    func animators(before: ResolvedSnapPointRange) -> [UIViewPropertyAnimator] {
      
      return backingStore
        .filter { $0.key.start >= before.start }
        .reduce(into: [UIViewPropertyAnimator]()) { (result, args) in
          result += args.value
      }
      
    }
    
    func allAnimators() -> [UIViewPropertyAnimator] {
      
      return
        backingStore.reduce(into: [UIViewPropertyAnimator]()) { (result, args) in
          result += args.value
      }
      
    }
    
    mutating func removeAllAnimations() {
      backingStore.removeAll()
    }
    
  }
  
  private struct ResolvedConfiguration {
    
    private(set) var snapPoints: [ResolvedSnapPoint] = []
    
    mutating func set<T : Collection>(snapPoints: T) where T.Element == ResolvedSnapPoint {
      self.snapPoints = snapPoints.sorted(by: <)
    }
    
    enum Location {
      case between(ResolvedSnapPointRange)
      case exact(ResolvedSnapPoint)
      case outOf(ResolvedSnapPoint)
    }
    
    func currentLocation(from currentPoint: CGFloat) -> Location {
      
      if let point = snapPoints.first(where: { $0.pointsFromTop == currentPoint }) {
        return .exact(point)
      }
      
      precondition(!snapPoints.isEmpty)
      
      let firstHalf = snapPoints.lazy.filter { $0.pointsFromTop <= currentPoint }
      let secondHalf = snapPoints.lazy.filter { $0.pointsFromTop >= currentPoint }
      
      if !firstHalf.isEmpty && !secondHalf.isEmpty {
        
        return .between(ResolvedSnapPointRange(firstHalf.last!, b:  secondHalf.first!))
      }
      
      if firstHalf.isEmpty {
        return .outOf(secondHalf.first!)
      }
      
      if secondHalf.isEmpty {
        return .outOf(firstHalf.last!)
      }
      
      fatalError()
      
    }
  }
}