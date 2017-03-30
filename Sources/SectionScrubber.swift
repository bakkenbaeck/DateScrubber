import UIKit

public protocol SectionScrubberDelegate: class {
    func sectionScrubberDidStartScrubbing(_ sectionScrubber: SectionScrubber)

    func sectionScrubberDidStopScrubbing(_ sectionScrubber: SectionScrubber)
}

public protocol SectionScrubberDataSource: class {
    func sectionScrubber(_ sectionScrubber: SectionScrubber, titleForSectionAtIndexPath indexPath: IndexPath) -> String
}

public class SectionScrubber: UIView {
    public enum SectionScrubberState {
        case hidden
        case scrolling
        case scrubbing
    }

    #if os(iOS)
    private let sectionScrubberHeight: CGFloat = 42
    #else
    private let sectionScrubberHeight: CGFloat = 100
    #endif

    private let sectionScrubberWidthHiding: CGFloat = 4
    private let sectionScrubberWidthScrubbing: CGFloat = 200

    private let sectionScrubberRightMarginHidden: CGFloat = 1

    #if os(iOS)
    private let sectionScrubberWidthScrolling: CGFloat = 140
    private let sectionScrubberRightMarginScrolling: CGFloat = 1
    #else
    private let sectionScrubberWidthScrolling: CGFloat = 280
    private let sectionScrubberRightMarginScrolling: CGFloat = -120
    #endif

    private let animationDuration: TimeInterval = 0.4
    private let animationDamping: CGFloat = 0.8
    private let animationSpringVelocity: CGFloat = 10

    public weak var delegate: SectionScrubberDelegate?
    public weak var dataSource: SectionScrubberDataSource?

    private var adjustedContainerBoundsHeight: CGFloat {
        guard let collectionView = self.collectionView else { return 0 }
        return collectionView.bounds.height - (collectionView.contentInset.top + collectionView.contentInset.bottom + self.frame.height)
    }

    private var adjustedContainerOrigin: CGFloat {
        guard let collectionView = self.collectionView else { return 0 }
        guard let window = collectionView.window else { return 0 }

        /*
         We check against the `UICollectionViewControllerWrapperView`, because this indicates we're working with
         a collection view that is inside a collection view controller. When that is the case, we have to deal with its
         superview instead of with it directly, otherwise we have a offsetting problem.
         */
        if collectionView.superview?.isKind(of: NSClassFromString(String.init(format: "U%@ectionViewCont%@w", "IColl", "rollerWrapperVie"))!) != nil {
            return (collectionView.superview?.convert(collectionView.frame.origin, to: window).y)!
        } else {
            return collectionView.convert(collectionView.frame.origin, to: window).y
        }
    }

    private var adjustedContainerHeight: CGFloat {
        guard let collectionView = self.collectionView else { return 0 }
        return collectionView.contentSize.height - collectionView.bounds.height + (collectionView.contentInset.top + collectionView.contentInset.bottom)
    }

    private var adjustedContainerOffset: CGFloat {
        guard let collectionView = self.collectionView else { return 0 }
        return collectionView.contentOffset.y + collectionView.contentInset.top
    }

    private var containingViewFrame: CGRect {
        return self.superview?.frame ?? CGRect.zero
    }

    fileprivate lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        UIPanGestureRecognizer()
    }()

    fileprivate lazy var longPressGestureRecognizer: UILongPressGestureRecognizer = {
        UILongPressGestureRecognizer()
    }()

    private weak var collectionView: UICollectionView?

    private var topConstraint: NSLayoutConstraint?

    private lazy var sectionScrubberImageRightConstraint: NSLayoutConstraint = {
        self.sectionScrubberImageView.rightAnchor.constraint(equalTo: self.rightAnchor)
    }()

    private lazy var sectionScrubberWidthConstraint: NSLayoutConstraint = {
        self.sectionScrubberContainer.widthAnchor.constraint(equalToConstant: 4)
    }()

    private lazy var sectionScrubberRightConstraint: NSLayoutConstraint = {
        self.sectionScrubberContainer.rightAnchor.constraint(equalTo: self.rightAnchor, constant: 1)
    }()

    fileprivate lazy var sectionScrubberContainer: UIView = {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = true
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.backgroundColor = self.containerColor
        #if os(iOS)
            container.layer.cornerRadius = 4
        #else
            container.layer.cornerRadius = 12
        #endif
        container.layer.masksToBounds = true

        container.heightAnchor.constraint(equalToConstant: self.sectionScrubberHeight).isActive = true

        return container
    }()

    fileprivate lazy var sectionScrubberImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        imageView.image = UIImage(named: "scrubber-arrows")
        imageView.heightAnchor.constraint(equalToConstant: 18).isActive = true
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true

        return imageView
    }()

    public var sectionScrubberState = SectionScrubberState.hidden {
        didSet {
            if self.sectionScrubberState != oldValue {
                self.updateSectionTitle()
                self.animateSectionScrubberState(self.sectionScrubberState, animated: true)
            }
        }
    }

    public var font: UIFont? {
        didSet {
            if let font = self.font {
                self.sectionScrubberTitle.font = font
            }
        }
    }

    public var textColor: UIColor? {
        didSet {
            if let textColor = self.textColor {
                 self.sectionScrubberTitle.textColor = textColor
            }
        }
    }

    public var containerColor: UIColor? {
        didSet {
            if let containerColor = self.containerColor {
                self.sectionScrubberContainer.backgroundColor = containerColor
            }
        }
    }

    fileprivate lazy var sectionScrubberTitle: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = self.textColor
        label.font = self.font
        label.heightAnchor.constraint(equalToConstant: self.sectionScrubberHeight).isActive = true

        return label
    }()

    public init(collectionView: UICollectionView?) {
        self.collectionView = collectionView

        super.init(frame: CGRect.zero)
        translatesAutoresizingMaskIntoConstraints = false

        heightAnchor.constraint(equalToConstant: self.sectionScrubberHeight).isActive = true

        self.panGestureRecognizer.addTarget(self, action: #selector(self.handleScrub))
        self.panGestureRecognizer.delegate = self
        addGestureRecognizer(self.panGestureRecognizer)

        self.longPressGestureRecognizer.addTarget(self, action: #selector(self.handleScrub))
        self.longPressGestureRecognizer.minimumPressDuration = 0.001
        self.longPressGestureRecognizer.delegate = self
        addGestureRecognizer(self.longPressGestureRecognizer)

        addSubview(self.sectionScrubberContainer)
        self.sectionScrubberRightConstraint.isActive = true
        self.sectionScrubberContainer.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        self.sectionScrubberWidthConstraint.isActive = true

        #if os(iOS)
            self.sectionScrubberContainer.addSubview(self.sectionScrubberImageView)
            self.sectionScrubberImageView.centerYAnchor.constraint(equalTo: self.sectionScrubberContainer.centerYAnchor).isActive = true
            self.sectionScrubberImageView.trailingAnchor.constraint(equalTo: self.sectionScrubberContainer.trailingAnchor, constant: -3).isActive = true
        #endif

        self.sectionScrubberContainer.addSubview(self.sectionScrubberTitle)

        self.sectionScrubberTitle.rightAnchor.constraint(equalTo: self.sectionScrubberContainer.rightAnchor).isActive = true
        self.sectionScrubberTitle.leftAnchor.constraint(lessThanOrEqualTo: self.sectionScrubberContainer.leftAnchor, constant: 20).isActive = true
        self.sectionScrubberTitle.centerYAnchor.constraint(equalTo: self.sectionScrubberContainer.centerYAnchor).isActive = true
    }

    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        self.animateSectionScrubberState(self.sectionScrubberState, animated: false)

        if let superview = self.superview {
            self.leftAnchor.constraint(equalTo: superview.leftAnchor).isActive = true
            self.rightAnchor.constraint(equalTo: superview.rightAnchor).isActive = true
            self.centerXAnchor.constraint(equalTo: superview.centerXAnchor).isActive = true

            self.topConstraint = self.topAnchor.constraint(equalTo: superview.topAnchor)
            self.topConstraint?.isActive = true
        }
    }

    private func hideSectionScrubberAfterDelay() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideSectionScrubber), object: nil)
        perform(#selector(self.hideSectionScrubber), with: nil, afterDelay: 2)
    }

    public func updateScrubberPosition() {
        guard let collectionView = self.collectionView else { return }
        guard collectionView.contentSize.height != 0 else { return }

        if sectionScrubberState == .hidden {
            self.sectionScrubberState = .scrolling
        }
        self.hideSectionScrubberAfterDelay()

        let percentage = boundedPercentage(collectionView.contentOffset.y / self.adjustedContainerHeight)
        let newY = self.adjustedContainerOffset + (self.adjustedContainerBoundsHeight * percentage)
        self.topConstraint?.constant = newY

        updateSectionTitle()
    }

    /*
     * Only process touch events if we're hitting the actual sectionScrubber image.
     * Every other touch is ignored.
     */
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {

        let hitWidth: CGFloat = 60
        let hitFrame = CGRect(x: frame.width - hitWidth, y: 0, width: hitWidth, height: frame.height)

        if hitFrame.contains(point) {
            return super.hitTest(point, with: event)
        }

        return nil
    }

    /**
     Initial dragging doesn't take in account collection view headers, just cells, so before the sectionScrubber reaches
     a cell, this is not going to return an index path.
     **/
    private func indexPath(at point: CGPoint) -> IndexPath? {
        guard let collectionView = self.collectionView else { return nil }
        if let indexPath = collectionView.indexPathForItem(at: point) {
            return indexPath
        }
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionElementKindSectionHeader) {
            guard let view = collectionView.supplementaryView(forElementKind: UICollectionElementKindSectionHeader, at: indexPath) else { continue }
            if view.frame.contains(point) {
                return indexPath
            }
        }
        return nil
    }

    private func updateSectionTitle() {
        // This makes too many assumptions about the collection view layout. 😔
        // It just uses 0, because it works for now, but we might need to come up with a better method for this.
        let centerPoint = CGPoint(x: 0, y: center.y)
        if let indexPath = self.indexPath(at: centerPoint) {
            if let title = self.dataSource?.sectionScrubber(self, titleForSectionAtIndexPath: indexPath) {
                self.updateSectionTitle(with: title)
            }
        } else if center.y < self.collectionView?.contentInset.top ?? 0 {
            if let title = dataSource?.sectionScrubber(self, titleForSectionAtIndexPath: IndexPath.init(item: 0, section: 0)) {
                self.updateSectionTitle(with: title)
            }
        }
    }

    private func updateSectionTitle(with title: String) {
        self.sectionScrubberTitle.text = title.uppercased()
    }

    private var previousLocation: CGFloat = 0

    func handleScrub(_ gesture: UIPanGestureRecognizer) {
        guard let collectionView = self.collectionView else { return }
        guard let window = collectionView.window else { return }
        guard containingViewFrame.height != 0 else { return }

        if gesture.state == .began {
            self.startScrubbing()
        }

        if gesture.state == .began || gesture.state == .changed || gesture.state == .ended {
            let locationInCollectionView = gesture.location(in: collectionView)
            let locationInWindow = collectionView.convert(locationInCollectionView, to: window)
            let location = locationInWindow.y - (self.adjustedContainerOrigin + collectionView.contentInset.top + collectionView.contentInset.bottom)

            if gesture.state != .began && location != self.previousLocation {
                let gesturePercentage = self.boundedPercentage(location / self.adjustedContainerBoundsHeight)
                let y = (self.adjustedContainerHeight * gesturePercentage) - collectionView.contentInset.top
                collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: y), animated: false)
            }

            self.previousLocation = location
            self.hideSectionScrubberAfterDelay()
        }

        if gesture.state == .ended || gesture.state == .cancelled {
            self.stopScrubbing()
        }
    }

    private func boundedPercentage(_ percentage: CGFloat) -> CGFloat {
        var newPercentage = percentage

        newPercentage = max(newPercentage, 0.0)
        newPercentage = min(newPercentage, 1.0)

        return newPercentage
    }

    private func animateSectionScrubberState(_ state: SectionScrubberState, animated: Bool) {
        let duration = animated ? self.animationDuration : 0.0
        var titleAlpha: CGFloat = 1

        switch state {
        case .hidden:
            self.sectionScrubberRightConstraint.constant = self.sectionScrubberRightMarginHidden
            self.sectionScrubberWidthConstraint.constant = self.sectionScrubberWidthHiding
            titleAlpha = 0
        case .scrolling:
            self.sectionScrubberRightConstraint.constant = self.sectionScrubberRightMarginScrolling
            self.sectionScrubberWidthConstraint.constant = self.sectionScrubberWidthScrolling
        case .scrubbing:
            self.sectionScrubberRightConstraint.constant = self.sectionScrubberRightMarginHidden
            self.sectionScrubberWidthConstraint.constant = self.sectionScrubberWidthScrubbing
        }

        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: self.animationDamping, initialSpringVelocity: self.animationSpringVelocity, options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut], animations: {
            self.sectionScrubberTitle.alpha = titleAlpha
            let isIPhone5OrBelow = max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) <= 568.0
            if isIPhone5OrBelow {
                self.sectionScrubberContainer.layoutIfNeeded()
            } else {
                self.layoutIfNeeded()
            }
        }, completion: { _ in })
    }

    private func startScrubbing() {
        self.delegate?.sectionScrubberDidStartScrubbing(self)
        self.sectionScrubberState = .scrubbing
    }

    private func stopScrubbing() {
        self.delegate?.sectionScrubberDidStopScrubbing(self)

        guard sectionScrubberState == .scrubbing else {
            return
        }

        self.sectionScrubberState = .scrolling
    }

    func hideSectionScrubber() {
        self.sectionScrubberState = .hidden
    }
}

extension SectionScrubber: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        
        if gestureRecognizer.view != self || otherGestureRecognizer.view == self {
            return false
        }
        
        return true
    }
}
