import SwiftUI
import UIKit

/// Precomputed row snapshot built off the main thread so 60/120 Hz scrolling does zero string formatting.
struct NativeSongRow: Equatable, Sendable {
    let song: Song
    let thumbnailURL: URL
    let subtitle: String
    let fileDetails: String
    let accessibilityLabel: String

    nonisolated static func build(song: Song, thumbnailURL: URL, showsFileDetails: Bool) -> NativeSongRow {
        let subtitle: String
        let artistBlank = song.artist.isBlank
        let albumBlank = song.album.isBlank
        if !artistBlank && !albumBlank {
            subtitle = "\(song.artist) - \(song.album)"
        } else if !artistBlank {
            subtitle = song.artist
        } else if !albumBlank {
            subtitle = song.album
        } else {
            subtitle = ""
        }
        return NativeSongRow(
            song: song,
            thumbnailURL: thumbnailURL,
            subtitle: subtitle,
            fileDetails: showsFileDetails ? SongRowText.fileDetails(song) : "",
            accessibilityLabel: SongRowText.accessibilityLabel(song, includingFileDetails: showsFileDetails)
        )
    }
}

/// Apple Music-style UIKit table view with recycled cells, fixed O(1) row height,
/// velocity-aware artwork prefetching, deferred menus, and instant non-animated index jumps.
struct NativeSongTableView<Header: View>: UIViewControllerRepresentable {
    let rows: [NativeSongRow]
    let currentSongID: Int64?
    let highlightedSongID: Int64?
    let selecting: Bool
    let selectedIDs: Set<Int64>
    let showsFileDetails: Bool
    let showsAlphabetPadding: Bool
    let emptyMessage: String
    let emptyIcon: String
    let isLoading: Bool
    let palette: AppPalette
    let colorScheme: ColorScheme
    let artworkChangeVersion: Int
    let scrollHandle: NativeScrollHandle
    let actions: SongActions
    let accessibilityIdentifier: String
    let onTapSong: (Int, Song) -> Void
    let onToggleSelect: (Song) -> Void
    let onRefresh: () -> Void
    @ViewBuilder let header: () -> Header

    func makeUIViewController(context: Context) -> NativeSongTableController<Header> {
        NativeSongTableController(header: header(), accessibilityIdentifier: accessibilityIdentifier)
    }

    func updateUIViewController(_ controller: NativeSongTableController<Header>, context: Context) {
        controller.apply(
            rows: rows,
            currentSongID: currentSongID,
            highlightedSongID: highlightedSongID,
            selecting: selecting,
            selectedIDs: selectedIDs,
            showsFileDetails: showsFileDetails,
            showsAlphabetPadding: showsAlphabetPadding,
            emptyMessage: emptyMessage,
            emptyIcon: emptyIcon,
            isLoading: isLoading,
            palette: palette,
            colorScheme: colorScheme,
            artworkChangeVersion: artworkChangeVersion,
            scrollHandle: scrollHandle,
            actions: actions,
            header: header(),
            onTapSong: onTapSong,
            onToggleSelect: onToggleSelect,
            onRefresh: onRefresh
        )
    }
}

@MainActor
final class NativeSongTableController<Header: View>: UITableViewController, UITableViewDataSourcePrefetching {
    private static let cellID = "NativeSongCell"
    private let headerHost: UIHostingController<Header>
    private let emptyContainer = UIView()
    private let emptyIconView = UIImageView()
    private let emptyLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let tableAccessibilityID: String

    private var rows: [NativeSongRow] = []
    private var currentSongID: Int64?
    private var highlightedSongID: Int64?
    private var selecting = false
    private var selectedIDs: Set<Int64> = []
    private var showsFileDetails = true
    private var showsAlphabetPadding = false
    private var palette = AppPalette.light
    private var colorScheme: ColorScheme = .light
    private var artworkChangeVersion = 0
    private var actions: SongActions?
    private var onTapSong: ((Int, Song) -> Void)?
    private var onToggleSelect: ((Song) -> Void)?
    private var onRefresh: (() -> Void)?
    private var lastHeaderWidth: CGFloat = 0
    private var lastHeaderHeight: CGFloat = 0

    init(header: Header, accessibilityIdentifier: String) {
        self.headerHost = UIHostingController(rootView: header)
        self.tableAccessibilityID = accessibilityIdentifier
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.showsVerticalScrollIndicator = false
        tableView.keyboardDismissMode = .interactive
        tableView.rowHeight = 70
        tableView.estimatedRowHeight = 0
        tableView.estimatedSectionHeaderHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.contentInsetAdjustmentBehavior = .automatic
        tableView.accessibilityIdentifier = tableAccessibilityID
        tableView.register(NativeSongCell.self, forCellReuseIdentifier: Self.cellID)
        tableView.prefetchDataSource = self

        let refresher = UIRefreshControl()
        refresher.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        refreshControl = refresher

        addChild(headerHost)
        headerHost.safeAreaRegions = []
        headerHost.view.backgroundColor = .clear
        tableView.tableHeaderView = headerHost.view
        headerHost.didMove(toParent: self)

        configureEmptyStateView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = tableView.bounds.width
        if width > 0 && abs(width - lastHeaderWidth) > 0.5 {
            lastHeaderWidth = width
            layoutHeaderIfNeeded(force: true)
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
        refreshControl?.endRefreshing()
    }

    func apply(
        rows: [NativeSongRow],
        currentSongID: Int64?,
        highlightedSongID: Int64?,
        selecting: Bool,
        selectedIDs: Set<Int64>,
        showsFileDetails: Bool,
        showsAlphabetPadding: Bool,
        emptyMessage: String,
        emptyIcon: String,
        isLoading: Bool,
        palette: AppPalette,
        colorScheme: ColorScheme,
        artworkChangeVersion: Int,
        scrollHandle: NativeScrollHandle,
        actions: SongActions,
        header: Header,
        onTapSong: @escaping (Int, Song) -> Void,
        onToggleSelect: @escaping (Song) -> Void,
        onRefresh: @escaping () -> Void
    ) {
        let rowsChanged = self.rows != rows
        let structureChanged = rowsChanged
            || self.selecting != selecting
            || self.showsFileDetails != showsFileDetails
            || self.showsAlphabetPadding != showsAlphabetPadding
            || self.palette != palette
            || self.colorScheme != colorScheme
            || self.artworkChangeVersion != artworkChangeVersion
        let visibleStateChanged = self.currentSongID != currentSongID
            || self.highlightedSongID != highlightedSongID
            || self.selectedIDs != selectedIDs

        self.rows = rows
        self.currentSongID = currentSongID
        self.highlightedSongID = highlightedSongID
        self.selecting = selecting
        self.selectedIDs = selectedIDs
        self.showsFileDetails = showsFileDetails
        self.showsAlphabetPadding = showsAlphabetPadding
        self.palette = palette
        self.colorScheme = colorScheme
        self.artworkChangeVersion = artworkChangeVersion
        self.actions = actions
        self.onTapSong = onTapSong
        self.onToggleSelect = onToggleSelect
        self.onRefresh = onRefresh

        scrollHandle.scrollToRow = { [weak self] index, position, animated in
            guard let self, index >= 0, index < self.tableView.numberOfRows(inSection: 0) else { return }
            self.tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: position, animated: animated)
        }

        let targetRowHeight: CGFloat = showsFileDetails ? 70 : 62
        if tableView.rowHeight != targetRowHeight {
            tableView.rowHeight = targetRowHeight
        }

        headerHost.rootView = header
        layoutHeaderIfNeeded(force: false)
        updateEmptyState(isLoading: isLoading, message: emptyMessage, icon: emptyIcon)

        if structureChanged {
            tableView.reloadData()
        } else if visibleStateChanged {
            reconfigureVisibleCells()
        }
    }

    private func layoutHeaderIfNeeded(force: Bool) {
        let width = tableView.bounds.width
        guard width > 0 else { return }
        headerHost.view.setNeedsLayout()
        headerHost.view.layoutIfNeeded()
        let measured = headerHost.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        if force || abs(measured - lastHeaderHeight) > 0.5 || abs(headerHost.view.frame.width - width) > 0.5 {
            lastHeaderHeight = measured
            headerHost.view.frame = CGRect(x: 0, y: 0, width: width, height: measured)
            tableView.tableHeaderView = headerHost.view
        }
    }

    private func updateEmptyState(isLoading: Bool, message: String, icon: String) {
        guard rows.isEmpty else {
            if tableView.backgroundView != nil { tableView.backgroundView = nil }
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
        if tableView.backgroundView !== emptyContainer {
            tableView.backgroundView = emptyContainer
        }
    }

    private func reconfigureVisibleCells() {
        guard let visible = tableView.indexPathsForVisibleRows else { return }
        for indexPath in visible where indexPath.row < rows.count {
            if let cell = tableView.cellForRow(at: indexPath) as? NativeSongCell {
                configure(cell, at: indexPath.row)
            }
        }
    }

    private func configure(_ cell: NativeSongCell, at index: Int) {
        let row = rows[index]
        let isCurrent = row.song.id == currentSongID
        let isHighlighted = row.song.id == highlightedSongID
        let isSelected = selectedIDs.contains(row.song.id)
        let trailingPad: CGFloat = showsAlphabetPadding ? SongAlphabetMetrics.width : 4
        let songActions = actions
        cell.configure(
            row: row,
            isCurrent: isCurrent,
            isHighlighted: isHighlighted,
            selecting: selecting,
            isSelected: isSelected,
            showsFileDetails: showsFileDetails,
            trailingInset: trailingPad,
            palette: palette,
            artworkChangeVersion: artworkChangeVersion,
            menuProvider: { [weak self] in
                guard let actions = self?.actions ?? songActions else { return UIMenu(children: []) }
                return makeAppleMusicSongMenu(song: row.song, actions: actions)
            },
            onTap: { [weak self] in
                guard let self else { return }
                if self.selecting {
                    self.onToggleSelect?(row.song)
                } else {
                    self.onTapSong?(index, row.song)
                }
            }
        )
    }

    // MARK: - UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellID, for: indexPath) as? NativeSongCell else {
            return UITableViewCell()
        }
        configure(cell, at: indexPath.row)
        return cell
    }

    // MARK: - UITableViewDataSourcePrefetching

    func tableView(_ tableView: UITableView, prefetchRowsAt indexPaths: [IndexPath]) {
        var urls: [URL] = []
        urls.reserveCapacity(indexPaths.count)
        for indexPath in indexPaths where indexPath.row < rows.count {
            urls.append(rows[indexPath.row].thumbnailURL)
        }
        ArtworkLoader.shared.prefetch(urls: urls, maxPixels: 144)
    }

    // MARK: - Swipe actions (native UIKit, zero per-row gesture UIViewRepresentables)

    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !selecting, indexPath.row < rows.count, let actions else { return nil }
        let song = rows[indexPath.row].song
        let queue = UIContextualAction(style: .normal, title: L("Add to queue")) { _, _, done in
            actions.addToQueue(song)
            done(true)
        }
        queue.image = UIImage(systemName: "text.badge.plus")
        queue.backgroundColor = UIColor(palette.primary)
        let config = UISwipeActionsConfiguration(actions: [queue])
        config.performsFirstActionWithFullSwipe = true
        return config
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !selecting, indexPath.row < rows.count, let actions else { return nil }
        let song = rows[indexPath.row].song
        let title = song.isFavorite ? L("Remove from favorites") : L("Add to favorites")
        let fav = UIContextualAction(style: .normal, title: title) { _, _, done in
            actions.toggleFavorite(song)
            done(true)
        }
        fav.image = UIImage(systemName: song.isFavorite ? "heart.slash" : "heart.fill")
        fav.backgroundColor = UIColor(palette.primary)
        let config = UISwipeActionsConfiguration(actions: [fav])
        config.performsFirstActionWithFullSwipe = true
        return config
    }

    // MARK: - Apple Music Context Menu (Image 2 reference)

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !selecting, indexPath.row < rows.count, let actions else { return nil }
        let row = rows[indexPath.row]
        let currentPalette = palette
        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: { NativeSongPreviewController(row: row, palette: currentPalette) },
            actionProvider: { _ in makeAppleMusicSongMenu(song: row.song, actions: actions) }
        )
    }
}

/// Recycled UIKit cell for song lists: zero SwiftUI view graph overhead, O(1) layout, synchronous cached artwork.
private final class NativeSongCell: UITableViewCell {
    private let rowTapTarget = UIControl()
    private let selectionImageView = UIImageView()
    private let artworkContainer = UIView()
    private let artworkImageView = UIImageView()
    private let placeholderImageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailsRow = UIStackView()
    private let noteIconView = UIImageView()
    private let detailsLabel = UILabel()
    private let heartIconView = UIImageView()
    private let moreButton = UIButton(type: .system)

    private var selectionWidthConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    private var moreWidthConstraint: NSLayoutConstraint!
    private var artworkTask: Task<Void, Never>?
    private var currentArtworkKey = ""
    private var onTapHandler: (() -> Void)?
    private var menuProvider: (() -> UIMenu)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        isAccessibilityElement = false

        rowTapTarget.translatesAutoresizingMaskIntoConstraints = false
        rowTapTarget.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        rowTapTarget.isAccessibilityElement = true
        rowTapTarget.accessibilityTraits = .button
        contentView.addSubview(rowTapTarget)

        selectionImageView.translatesAutoresizingMaskIntoConstraints = false
        selectionImageView.contentMode = .center
        selectionImageView.isUserInteractionEnabled = false
        rowTapTarget.addSubview(selectionImageView)

        artworkContainer.translatesAutoresizingMaskIntoConstraints = false
        artworkContainer.layer.cornerRadius = 10
        artworkContainer.layer.cornerCurve = .continuous
        artworkContainer.clipsToBounds = true
        artworkContainer.isUserInteractionEnabled = false
        rowTapTarget.addSubview(artworkContainer)

        placeholderImageView.translatesAutoresizingMaskIntoConstraints = false
        placeholderImageView.image = UIImage(systemName: "music.note")
        placeholderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        placeholderImageView.contentMode = .center
        artworkContainer.addSubview(placeholderImageView)

        artworkImageView.translatesAutoresizingMaskIntoConstraints = false
        artworkImageView.contentMode = .scaleAspectFill
        artworkImageView.clipsToBounds = true
        artworkContainer.addSubview(artworkImageView)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.numberOfLines = 1

        subtitleLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.numberOfLines = 1

        noteIconView.image = UIImage(systemName: "music.note")
        noteIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        noteIconView.contentMode = .scaleAspectFit
        noteIconView.setContentHuggingPriority(.required, for: .horizontal)
        noteIconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        detailsLabel.font = .systemFont(ofSize: 11, weight: .medium)
        detailsLabel.lineBreakMode = .byTruncatingTail
        detailsLabel.numberOfLines = 1
        detailsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        heartIconView.image = UIImage(systemName: "heart.fill")
        heartIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        heartIconView.contentMode = .scaleAspectFit
        heartIconView.setContentHuggingPriority(.required, for: .horizontal)
        heartIconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        detailsRow.axis = .horizontal
        detailsRow.alignment = .center
        detailsRow.spacing = 4
        detailsRow.addArrangedSubview(noteIconView)
        detailsRow.addArrangedSubview(detailsLabel)
        detailsRow.addArrangedSubview(heartIconView)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, detailsRow])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false
        rowTapTarget.addSubview(textStack)

        moreButton.translatesAutoresizingMaskIntoConstraints = false
        let ellipsis = UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        moreButton.setImage(ellipsis, for: .normal)
        moreButton.imageView?.transform = CGAffineTransform(rotationAngle: .pi / 2)
        moreButton.showsMenuAsPrimaryAction = true
        moreButton.accessibilityLabel = L("More options")
        moreButton.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                guard let self, let menu = self.menuProvider?() else { completion([]); return }
                completion(menu.children)
            },
        ])
        contentView.addSubview(moreButton)

        selectionWidthConstraint = selectionImageView.widthAnchor.constraint(equalToConstant: 0)
        moreWidthConstraint = moreButton.widthAnchor.constraint(equalToConstant: 30)
        trailingConstraint = moreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4)

        NSLayoutConstraint.activate([
            rowTapTarget.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Spacing.md),
            rowTapTarget.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowTapTarget.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rowTapTarget.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -2),

            selectionImageView.leadingAnchor.constraint(equalTo: rowTapTarget.leadingAnchor),
            selectionImageView.centerYAnchor.constraint(equalTo: rowTapTarget.centerYAnchor),
            selectionWidthConstraint,
            selectionImageView.heightAnchor.constraint(equalToConstant: 36),

            artworkContainer.leadingAnchor.constraint(equalTo: selectionImageView.trailingAnchor),
            artworkContainer.centerYAnchor.constraint(equalTo: rowTapTarget.centerYAnchor),
            artworkContainer.widthAnchor.constraint(equalToConstant: 52),
            artworkContainer.heightAnchor.constraint(equalToConstant: 52),

            placeholderImageView.centerXAnchor.constraint(equalTo: artworkContainer.centerXAnchor),
            placeholderImageView.centerYAnchor.constraint(equalTo: artworkContainer.centerYAnchor),

            artworkImageView.leadingAnchor.constraint(equalTo: artworkContainer.leadingAnchor),
            artworkImageView.trailingAnchor.constraint(equalTo: artworkContainer.trailingAnchor),
            artworkImageView.topAnchor.constraint(equalTo: artworkContainer.topAnchor),
            artworkImageView.bottomAnchor.constraint(equalTo: artworkContainer.bottomAnchor),

            textStack.leadingAnchor.constraint(equalTo: artworkContainer.trailingAnchor, constant: Spacing.md),
            textStack.trailingAnchor.constraint(equalTo: rowTapTarget.trailingAnchor),
            textStack.centerYAnchor.constraint(equalTo: rowTapTarget.centerYAnchor),

            trailingConstraint,
            moreButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            moreWidthConstraint,
            moreButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    @objc private func handleTap() {
        onTapHandler?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        artworkTask?.cancel()
        artworkTask = nil
        currentArtworkKey = ""
        artworkImageView.image = nil
        placeholderImageView.isHidden = false
        onTapHandler = nil
        menuProvider = nil
    }

    func configure(
        row: NativeSongRow,
        isCurrent: Bool,
        isHighlighted: Bool,
        selecting: Bool,
        isSelected: Bool,
        showsFileDetails: Bool,
        trailingInset: CGFloat,
        palette: AppPalette,
        artworkChangeVersion: Int,
        menuProvider: @escaping () -> UIMenu,
        onTap: @escaping () -> Void
    ) {
        self.onTapHandler = onTap
        self.menuProvider = menuProvider

        let primary = UIColor(palette.primary)
        let onSurface = UIColor(palette.onSurface)
        let onSurfaceVariant = UIColor(palette.onSurfaceVariant)
        let surfaceVariant = UIColor(palette.surfaceVariant)

        contentView.backgroundColor = isHighlighted ? primary.withAlphaComponent(PlayerButtonConstants.highlightOpacity) : .clear

        selectionWidthConstraint.constant = selecting ? 36 : 0
        selectionImageView.isHidden = !selecting
        if selecting {
            selectionImageView.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            selectionImageView.tintColor = isSelected ? primary : onSurfaceVariant
        }

        moreButton.isHidden = selecting
        moreWidthConstraint.constant = selecting ? 0 : 30
        trailingConstraint.constant = -trailingInset
        moreButton.tintColor = onSurfaceVariant.withAlphaComponent(0.75)

        titleLabel.text = row.song.title
        titleLabel.textColor = isCurrent ? primary : onSurface
        subtitleLabel.text = row.subtitle
        subtitleLabel.textColor = onSurfaceVariant

        if showsFileDetails {
            detailsRow.isHidden = false
            noteIconView.isHidden = false
            detailsLabel.isHidden = false
            noteIconView.tintColor = primary.withAlphaComponent(0.78)
            detailsLabel.text = row.fileDetails
            detailsLabel.textColor = primary.withAlphaComponent(0.78)
            heartIconView.isHidden = !row.song.isFavorite
            heartIconView.tintColor = primary
        } else if row.song.isFavorite {
            detailsRow.isHidden = false
            noteIconView.isHidden = true
            detailsLabel.isHidden = true
            heartIconView.isHidden = false
            heartIconView.tintColor = primary
        } else {
            detailsRow.isHidden = true
        }

        rowTapTarget.accessibilityLabel = row.accessibilityLabel
        rowTapTarget.accessibilityValue = selecting ? (isSelected ? "Selected" : "Not selected") : nil
        accessibilityElements = selecting ? [rowTapTarget] : [rowTapTarget, moreButton]

        artworkContainer.backgroundColor = surfaceVariant
        placeholderImageView.tintColor = onSurfaceVariant

        let artKey = "\(row.thumbnailURL.path)|\(artworkChangeVersion)"
        if currentArtworkKey != artKey {
            artworkTask?.cancel()
            currentArtworkKey = artKey
            if let cached = ArtworkLoader.shared.cachedImage(for: row.thumbnailURL, maxPixels: 144, fallbackSizes: [600, 320]) {
                artworkImageView.image = cached
                placeholderImageView.isHidden = true
            } else {
                artworkImageView.image = nil
                placeholderImageView.isHidden = false
                let url = row.thumbnailURL
                artworkTask = Task { @MainActor [weak self] in
                    let loaded = await ArtworkLoader.shared.image(for: url, maxPixels: 144)
                    guard let self, !Task.isCancelled, self.currentArtworkKey == artKey else { return }
                    self.artworkImageView.image = loaded
                    self.placeholderImageView.isHidden = loaded != nil
                }
            }
        }
    }
}

/// Apple Music-style context menu preview card (opaque rounded card with cover, title, artist, and chevron).
private final class NativeSongPreviewController: UIViewController {
    private let row: NativeSongRow
    private let palette: AppPalette
    private let artworkView = UIImageView()
    private let placeholderView = UIImageView()

    init(row: NativeSongRow, palette: AppPalette) {
        self.row = row
        self.palette = palette
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 316, height: 86)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(palette.surface)

        let artBox = UIView()
        artBox.translatesAutoresizingMaskIntoConstraints = false
        artBox.backgroundColor = UIColor(palette.surfaceVariant)
        artBox.layer.cornerRadius = 10
        artBox.layer.cornerCurve = .continuous
        artBox.clipsToBounds = true

        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.image = UIImage(systemName: "music.note")
        placeholderView.tintColor = UIColor(palette.onSurfaceVariant)
        artBox.addSubview(placeholderView)

        artworkView.translatesAutoresizingMaskIntoConstraints = false
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artBox.addSubview(artworkView)

        if let cached = ArtworkLoader.shared.cachedImage(for: row.thumbnailURL, maxPixels: 144, fallbackSizes: [600, 320]) {
            artworkView.image = cached
            placeholderView.isHidden = true
        } else {
            let url = row.thumbnailURL
            Task { @MainActor [weak self] in
                let loaded = await ArtworkLoader.shared.image(for: url, maxPixels: 144)
                guard let self, let loaded else { return }
                self.artworkView.image = loaded
                self.placeholderView.isHidden = true
            }
        }

        let titleLabel = UILabel()
        titleLabel.text = row.song.title
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = UIColor(palette.onSurface)
        titleLabel.numberOfLines = 2

        let subLabel = UILabel()
        subLabel.text = row.subtitle
        subLabel.font = .systemFont(ofSize: 13.5, weight: .regular)
        subLabel.textColor = UIColor(palette.onSurfaceVariant)
        subLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subLabel])
        textStack.axis = .vertical
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        chevron.tintColor = UIColor(palette.onSurfaceVariant).withAlphaComponent(0.6)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        view.addSubview(artBox)
        view.addSubview(textStack)
        view.addSubview(chevron)

        NSLayoutConstraint.activate([
            artBox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            artBox.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            artBox.widthAnchor.constraint(equalToConstant: 58),
            artBox.heightAnchor.constraint(equalToConstant: 58),

            placeholderView.centerXAnchor.constraint(equalTo: artBox.centerXAnchor),
            placeholderView.centerYAnchor.constraint(equalTo: artBox.centerYAnchor),

            artworkView.leadingAnchor.constraint(equalTo: artBox.leadingAnchor),
            artworkView.trailingAnchor.constraint(equalTo: artBox.trailingAnchor),
            artworkView.topAnchor.constraint(equalTo: artBox.topAnchor),
            artworkView.bottomAnchor.constraint(equalTo: artBox.bottomAnchor),

            textStack.leadingAnchor.constraint(equalTo: artBox.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            chevron.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

/// Builds the Apple Music-style song UIMenu (top Favorite + Share inline row, Playlist, Queue,
/// Go to Album / Go to Artist with subtitles, Info & tags submenu, and destructive Delete).
@MainActor
func makeAppleMusicSongMenu(song: Song, actions: SongActions) -> UIMenu {
    var topActions: [UIAction] = [
        UIAction(
            title: song.isFavorite ? L("Remove from favorites") : L("Add to favorites"),
            image: UIImage(systemName: song.isFavorite ? "heart.slash" : "heart")
        ) { _ in actions.toggleFavorite(song) },
    ]
    if let share = actions.share {
        topActions.append(UIAction(title: L("Share"), image: UIImage(systemName: "square.and.arrow.up")) { _ in share(song) })
    }
    var sections: [UIMenuElement] = [
        UIMenu(title: "", options: .displayInline, preferredElementSize: .medium, children: topActions),
        UIMenu(title: "", options: .displayInline, children: [
            UIAction(title: L("Add to playlist"), image: UIImage(systemName: "text.badge.plus")) { _ in actions.addToPlaylist(song) },
        ]),
        UIMenu(title: "", options: .displayInline, children: [
            UIAction(title: L("Play next"), image: UIImage(systemName: "text.line.first.and.arrowtriangle.forward")) { _ in actions.playNext(song) },
            UIAction(title: L("Add to queue"), image: UIImage(systemName: "text.append")) { _ in actions.addToQueue(song) },
        ]),
    ]

    var navActions: [UIAction] = []
    if let goToAlbum = actions.goToAlbum, song.albumId != 0 {
        navActions.append(UIAction(
            title: L("Go to album"),
            subtitle: song.album.isBlank ? nil : song.album,
            image: UIImage(systemName: "square.stack")
        ) { _ in goToAlbum(song) })
    }
    if let goToArtist = actions.goToArtist, song.artistId != 0 {
        navActions.append(UIAction(
            title: L("Go to artist"),
            subtitle: song.artist.isBlank ? nil : song.artist,
            image: UIImage(systemName: "person")
        ) { _ in goToArtist(song) })
    }
    if !navActions.isEmpty {
        sections.append(UIMenu(title: "", options: .displayInline, children: navActions))
    }

    var infoChildren: [UIAction] = []
    if let view = actions.viewDetails {
        infoChildren.append(UIAction(title: L("View metadata"), image: UIImage(systemName: "info.circle")) { _ in view(song) })
    }
    if let edit = actions.editTags {
        infoChildren.append(UIAction(title: L("Edit tags"), image: UIImage(systemName: "pencil")) { _ in edit(song) })
    }
    if let fix = actions.fixTags {
        infoChildren.append(UIAction(title: L("Fix tags online"), image: UIImage(systemName: "wand.and.stars")) { _ in fix(song) })
    }
    if !infoChildren.isEmpty {
        sections.append(UIMenu(title: L("Info & tags"), image: UIImage(systemName: "info.circle"), children: infoChildren))
    }

    var destructive: [UIAction] = []
    if let remove = actions.removeFromPlaylist {
        destructive.append(UIAction(title: L("Remove from playlist"), image: UIImage(systemName: "minus.circle"), attributes: .destructive) { _ in remove(song) })
    }
    if let delete = actions.deleteFromDevice {
        destructive.append(UIAction(title: L("Delete from device"), image: UIImage(systemName: "trash"), attributes: .destructive) { _ in delete(song) })
    }
    if !destructive.isEmpty {
        sections.append(UIMenu(title: "", options: .displayInline, children: destructive))
    }

    return UIMenu(title: "", children: sections)
}
