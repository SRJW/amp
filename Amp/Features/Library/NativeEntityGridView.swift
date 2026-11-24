import SwiftUI
import UIKit

/// Precomputed tile snapshot for Albums, Artists, Album Artists, and Playlists grids.
struct NativeEntityItem: Equatable, Sendable {
    let id: Int64
    let title: String
    let subtitle: String?
    let audioArtworkURL: URL?
    let fileArtworkPath: String?
    let circular: Bool
    let monogram: String?
    let placeholderSymbol: String
}

/// Apple Music-style UIKit UICollectionView grid with cell recycling, velocity-aware
/// artwork prefetching, and O(1) instant non-animated alphabet jumping.
struct NativeEntityGridView<Header: View>: UIViewControllerRepresentable {
    let items: [NativeEntityItem]
    let showsAlphabetPadding: Bool
    let emptyMessage: String
    let emptyIcon: String
    let isLoading: Bool
    let palette: AppPalette
    let artworkChangeVersion: Int
    let scrollHandle: NativeScrollHandle
    let onSelect: (NativeEntityItem) -> Void
    let onRefresh: () -> Void
    @ViewBuilder let header: () -> Header

    func makeUIViewController(context: Context) -> NativeEntityGridController<Header> {
        NativeEntityGridController(header: header())
    }

    func updateUIViewController(_ controller: NativeEntityGridController<Header>, context: Context) {
        controller.apply(
            items: items,
            showsAlphabetPadding: showsAlphabetPadding,
            emptyMessage: emptyMessage,
            emptyIcon: emptyIcon,
            isLoading: isLoading,
            palette: palette,
            artworkChangeVersion: artworkChangeVersion,
            scrollHandle: scrollHandle,
            header: header(),
            onSelect: onSelect,
            onRefresh: onRefresh
        )
    }
}

@MainActor
final class NativeEntityGridController<Header: View>: UICollectionViewController, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching {
    private static var cellID: String { "NativeEntityTileCell" }
    private static var headerID: String { "NativeEntityGridHeader" }

    private let headerHost: UIHostingController<Header>
    private let emptyContainer = UIView()
    private let emptyIconView = UIImageView()
    private let emptyLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var items: [NativeEntityItem] = []
    private var showsAlphabetPadding = false
    private var palette = AppPalette.light
    private var artworkChangeVersion = 0
    private var onSelect: ((NativeEntityItem) -> Void)?
    private var onRefresh: (() -> Void)?
    private var cachedHeaderHeight: CGFloat = 0
    private var lastLayoutWidth: CGFloat = 0

    init(header: Header) {
        self.headerHost = UIHostingController(rootView: header)
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = Spacing.lg
        layout.minimumLineSpacing = Spacing.lg
        super.init(collectionViewLayout: layout)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.keyboardDismissMode = .interactive
        collectionView.contentInsetAdjustmentBehavior = .automatic
        let bottomClearance = AppNavigationMetrics.reservedHeight + 16
        collectionView.contentInset.bottom = bottomClearance
        collectionView.verticalScrollIndicatorInsets.bottom = bottomClearance
        collectionView.prefetchDataSource = self
        collectionView.register(NativeEntityTileCell.self, forCellWithReuseIdentifier: Self.cellID)
        collectionView.register(NativeGridHeaderReusableView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: Self.headerID)

        let refresher = UIRefreshControl()
        refresher.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        collectionView.refreshControl = refresher

        addChild(headerHost)
        headerHost.safeAreaRegions = []
        headerHost.view.backgroundColor = .clear
        headerHost.didMove(toParent: self)

        configureEmptyStateView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = collectionView.bounds.width
        if width > 0 && abs(width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = width
            remeasureHeader(width: width)
            collectionViewLayout.invalidateLayout()
        }
    }

    private func configureEmptyStateView() {
        emptyContainer.backgroundColor = .clear
        let stack = UIStackView(arrangedSubviews: [spinner, emptyIconView, emptyLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 32, weight: .medium)
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: emptyContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyContainer.centerYAnchor, constant: 40),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyContainer.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: emptyContainer.trailingAnchor, constant: -32),
        ])
    }

    @objc private func handleRefresh() {
        onRefresh?()
        collectionView.refreshControl?.endRefreshing()
    }

    func apply(
        items: [NativeEntityItem],
        showsAlphabetPadding: Bool,
        emptyMessage: String,
        emptyIcon: String,
        isLoading: Bool,
        palette: AppPalette,
        artworkChangeVersion: Int,
        scrollHandle: NativeScrollHandle,
        header: Header,
        onSelect: @escaping (NativeEntityItem) -> Void,
        onRefresh: @escaping () -> Void
    ) {
        let needsReload = self.items != items
            || self.showsAlphabetPadding != showsAlphabetPadding
            || self.palette != palette
            || self.artworkChangeVersion != artworkChangeVersion

        self.items = items
        self.showsAlphabetPadding = showsAlphabetPadding
        self.palette = palette
        self.artworkChangeVersion = artworkChangeVersion
        self.onSelect = onSelect
        self.onRefresh = onRefresh

        scrollHandle.scrollToGridItem = { [weak self] index, animated in
            guard let self, index >= 0, index < self.collectionView.numberOfItems(inSection: 0) else { return }
            self.collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .top, animated: animated)
        }

        headerHost.rootView = header
        let width = collectionView.bounds.width
        let previousHeight = cachedHeaderHeight
        if width > 0 { remeasureHeader(width: width) }
        updateEmptyState(isLoading: isLoading, message: emptyMessage, icon: emptyIcon)

        if needsReload {
            collectionView.reloadData()
        } else if abs(previousHeight - cachedHeaderHeight) > 0.5 {
            collectionViewLayout.invalidateLayout()
        }
    }

    private func remeasureHeader(width: CGFloat) {
        headerHost.view.setNeedsLayout()
        headerHost.view.layoutIfNeeded()
        let measured = headerHost.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        cachedHeaderHeight = max(measured, 0)
    }

    private func updateEmptyState(isLoading: Bool, message: String, icon: String) {
        guard items.isEmpty else {
            if collectionView.backgroundView != nil { collectionView.backgroundView = nil }
            return
        }
        let muted = UIColor(palette.onSurfaceVariant)
        if isLoading {
            spinner.color = muted
            spinner.startAnimating()
            spinner.isHidden = false
            emptyIconView.isHidden = true
            emptyLabel.isHidden = true
        } else {
            spinner.stopAnimating()
            spinner.isHidden = true
            emptyIconView.isHidden = false
            emptyLabel.isHidden = false
            emptyIconView.image = UIImage(systemName: icon)
            emptyIconView.tintColor = muted
            emptyLabel.text = message
            emptyLabel.textColor = muted
        }
        if collectionView.backgroundView !== emptyContainer {
            collectionView.backgroundView = emptyContainer
        }
    }

    // MARK: - UICollectionViewDataSource

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.cellID, for: indexPath) as? NativeEntityTileCell else {
            return UICollectionViewCell()
        }
        cell.configure(item: items[indexPath.item], palette: palette, artworkChangeVersion: artworkChangeVersion)
        return cell
    }

    override func collectionView(_ collectionView: UICollectionView,
                                 viewForSupplementaryElementOfKind kind: String,
                                 at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader,
              let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: Self.headerID, for: indexPath) as? NativeGridHeaderReusableView else {
            return UICollectionReusableView()
        }
        view.attach(headerHost.view)
        return view
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item < items.count else { return }
        onSelect?(items[indexPath.item])
    }

    // MARK: - UICollectionViewDelegateFlowLayout

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        let trailing = Spacing.gutter + (showsAlphabetPadding ? SongAlphabetMetrics.width : 0)
        return UIEdgeInsets(top: Spacing.sm, left: Spacing.gutter, bottom: Spacing.md, right: trailing)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        let width = collectionView.bounds.width
        guard width > 0 else { return .zero }
        if cachedHeaderHeight == 0 { remeasureHeader(width: width) }
        return CGSize(width: width, height: cachedHeaderHeight)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let trailing = Spacing.gutter + (showsAlphabetPadding ? SongAlphabetMetrics.width : 0)
        let available = max(collectionView.bounds.width - Spacing.gutter - trailing, 160)
        let columns = max(2, Int((available + Spacing.lg) / (ArtworkSize.gridMin + Spacing.lg)))
        let totalSpacing = Spacing.lg * CGFloat(columns - 1)
        let itemWidth = floor((available - totalSpacing) / CGFloat(columns))
        return CGSize(width: itemWidth, height: itemWidth + 46)
    }

    // MARK: - UICollectionViewDataSourcePrefetching

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        var urls: [URL] = []
        var paths: [String] = []
        for indexPath in indexPaths where indexPath.item < items.count {
            let item = items[indexPath.item]
            if let url = item.audioArtworkURL { urls.append(url) }
            if let path = item.fileArtworkPath { paths.append(path) }
        }
        if !urls.isEmpty { ArtworkLoader.shared.prefetch(urls: urls, maxPixels: 320) }
        if !paths.isEmpty { ArtworkLoader.shared.prefetchFiles(paths: paths, maxPixels: 320) }
    }
}

private final class NativeGridHeaderReusableView: UICollectionReusableView {
    func attach(_ hostedView: UIView) {
        guard hostedView.superview !== self else { return }
        hostedView.removeFromSuperview()
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

/// Recycled UIKit tile cell for Albums, Artists, Album Artists, and Playlists.
private final class NativeEntityTileCell: UICollectionViewCell {
    private let coverContainer = UIView()
    private let coverImageView = UIImageView()
    private let placeholderImageView = UIImageView()
    private let monogramLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private var artworkTask: Task<Void, Never>?
    private var currentKey = ""
    private var isCircular = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        coverContainer.translatesAutoresizingMaskIntoConstraints = false
        coverContainer.clipsToBounds = true
        contentView.addSubview(coverContainer)

        placeholderImageView.translatesAutoresizingMaskIntoConstraints = false
        placeholderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        placeholderImageView.contentMode = .center
        coverContainer.addSubview(placeholderImageView)

        monogramLabel.translatesAutoresizingMaskIntoConstraints = false
        monogramLabel.font = .systemFont(ofSize: 36, weight: .bold)
        monogramLabel.textAlignment = .center
        coverContainer.addSubview(monogramLabel)

        coverImageView.translatesAutoresizingMaskIntoConstraints = false
        coverImageView.contentMode = .scaleAspectFill
        coverImageView.clipsToBounds = true
        coverContainer.addSubview(coverImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1
        contentView.addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.numberOfLines = 1
        contentView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            coverContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            coverContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            coverContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            coverContainer.heightAnchor.constraint(equalTo: coverContainer.widthAnchor),

            placeholderImageView.centerXAnchor.constraint(equalTo: coverContainer.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: coverContainer.centerYAnchor),

            monogramLabel.centerXAnchor.constraint(equalTo: coverContainer.centerXAnchor),
            monogramLabel.centerYAnchor.constraint(equalTo: coverContainer.centerYAnchor),

            coverImageView.leadingAnchor.constraint(equalTo: coverContainer.leadingAnchor),
            coverImageView.trailingAnchor.constraint(equalTo: coverContainer.trailingAnchor),
            coverImageView.topAnchor.constraint(equalTo: coverContainer.topAnchor),
            coverImageView.bottomAnchor.constraint(equalTo: coverContainer.bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: coverContainer.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isCircular {
            coverContainer.layer.cornerRadius = coverContainer.bounds.width / 2
            coverContainer.layer.cornerCurve = .circular
        } else {
            coverContainer.layer.cornerRadius = Radius.medium
            coverContainer.layer.cornerCurve = .continuous
        }
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.14) {
                self.contentView.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
                self.contentView.alpha = self.isHighlighted ? 0.85 : 1.0
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkTask?.cancel()
        artworkTask = nil
        currentKey = ""
        coverImageView.image = nil
        placeholderImageView.isHidden = true
        monogramLabel.isHidden = true
    }

    func configure(item: NativeEntityItem, palette: AppPalette, artworkChangeVersion: Int) {
        isCircular = item.circular
        let onSurface = UIColor(palette.onSurface)
        let onSurfaceVariant = UIColor(palette.onSurfaceVariant)
        coverContainer.backgroundColor = UIColor(palette.surfaceVariant)

        titleLabel.text = item.title
        titleLabel.textColor = onSurface
        titleLabel.textAlignment = item.circular ? .center : .natural
        subtitleLabel.text = item.subtitle
        subtitleLabel.textColor = onSurfaceVariant
        subtitleLabel.textAlignment = item.circular ? .center : .natural
        subtitleLabel.isHidden = item.subtitle == nil

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = item.subtitle.map { "\(item.title), \($0)" } ?? item.title

        let showMonogram = item.monogram != nil
        monogramLabel.text = item.monogram
        monogramLabel.textColor = onSurface
        placeholderImageView.image = UIImage(systemName: item.placeholderSymbol)
        placeholderImageView.tintColor = onSurfaceVariant

        let sourceKey = item.audioArtworkURL?.path ?? item.fileArtworkPath ?? "none"
        let fullKey = "\(sourceKey)|\(artworkChangeVersion)"
        if currentKey != fullKey {
            artworkTask?.cancel()
            currentKey = fullKey
            if let url = item.audioArtworkURL {
                if let cached = ArtworkLoader.shared.cachedImage(for: url, maxPixels: 320, fallbackSizes: [600, 144]) {
                    coverImageView.image = cached
                    placeholderImageView.isHidden = true
                    monogramLabel.isHidden = true
                } else {
                    coverImageView.image = nil
                    placeholderImageView.isHidden = showMonogram
                    monogramLabel.isHidden = !showMonogram
                    artworkTask = Task { @MainActor [weak self] in
                        let loaded = await ArtworkLoader.shared.image(for: url, maxPixels: 320)
                        guard let self, !Task.isCancelled, self.currentKey == fullKey else { return }
                        self.coverImageView.image = loaded
                        self.placeholderImageView.isHidden = loaded != nil || showMonogram
                        self.monogramLabel.isHidden = loaded != nil || !showMonogram
                    }
                }
            } else if let path = item.fileArtworkPath {
                if let cached = ArtworkLoader.shared.cachedImage(atPath: path, maxPixels: 320) {
                    coverImageView.image = cached
                    placeholderImageView.isHidden = true
                    monogramLabel.isHidden = true
                } else {
                    coverImageView.image = nil
                    placeholderImageView.isHidden = showMonogram
                    monogramLabel.isHidden = !showMonogram
                    artworkTask = Task { @MainActor [weak self] in
                        let loaded = await ArtworkLoader.shared.image(atPath: path, maxPixels: 320)
                        guard let self, !Task.isCancelled, self.currentKey == fullKey else { return }
                        self.coverImageView.image = loaded
                        self.placeholderImageView.isHidden = loaded != nil || showMonogram
                        self.monogramLabel.isHidden = loaded != nil || !showMonogram
                    }
                }
            } else {
                coverImageView.image = nil
                placeholderImageView.isHidden = showMonogram
                monogramLabel.isHidden = !showMonogram
            }
        }
        setNeedsLayout()
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
