/*
 This code example is part of the Mapbox Navigation SDK for iOS demo app,
 which you can build and run: https://github.com/mapbox/mapbox-navigation-ios
 To learn more about the SDK, see our docs: https://docs.mapbox.com/ios/navigation
 */

import CoreLocation
import Foundation
@_spi(Experimental) import MapboxMaps
import UIKit

/// Manages a collection of building annotations on the map.
///
/// The manager provides default values for all fill extrusion properties. Individual annotations
/// can override these defaults by specifying their own values.
///
/// **Note:** Due to FillExtrusionLayer limitations, `fillExtrusionOpacity` is applied uniformly
/// to all buildings. Individual annotation opacity values are ignored.
///
/// ## Example Usage
/// ```swift
/// let manager = BuildingAnnotationManager(mapView: mapView)
/// // Set defaults for all annotations
/// manager.fillExtrusionColor = .green
/// manager.fillExtrusionOpacity = 0.9
/// manager.fillExtrusionHeight = 50.0
///
/// manager.annotations = [
///     BuildingAnnotation(coordinates: building1Points),  // Uses manager defaults
///     BuildingAnnotation(coordinates: building2Points, fillExtrusionHeight: 75.0)  // Overrides height
/// ]
/// ```
@MainActor
public final class BuildingAnnotationManager {
    private static var idGenerator: Int = 0

    private let mapView: MapView
    private let sourceId: String
    private let layerId: String
    private let symbolSourceId: String
    private let symbolLayerId: String
    private var isInitialized = false
    private var styleLoadedToken: Any?

    /// Setting this property updates the map with the new annotations.
    /// Uses a single source and layer with data-driven styling for efficient batch updates.
    public var annotations: [BuildingAnnotation] = [] {
        didSet { updateAnnotations() }
    }

    /// The default fillExtrusionColor for all annotations if not overwritten by individual annotation settings.
    /// Default value: blue (#3489F9)
    public var fillExtrusionColor: UIColor = UIColor(red: 0.204, green: 0.537, blue: 0.976, alpha: 1.0) {
        didSet { updateAnnotations() }
    }

    /// The default fillExtrusionOpacity for all annotations.
    /// This is a layer-level property that applies uniformly to all annotations.
    /// Individual annotation `fillExtrusionOpacity` values are ignored.
    /// Value range: [0, 1], where 0 is fully transparent and 1 is fully opaque.
    /// Default value: 0.8
    public var fillExtrusionOpacity: Double = 0.8 {
        didSet { updateLayerOpacity() }
    }

    /// The default fillExtrusionHeight for all annotations if not overwritten by individual annotation settings.
    /// Default value: 50.0 meters
    public var fillExtrusionHeight: Double = 50.0 {
        didSet { updateAnnotations() }
    }

    /// The default fillExtrusionBase for all annotations if not overwritten by individual annotation settings.
    /// Default value: 0.0 meters
    public var fillExtrusionBase: Double = 0.0 {
        didSet { updateAnnotations() }
    }

    /// The default label text color for the day light preset.
    /// Default value: #404040
    public var textColor: UIColor = UIColor(red: 0.251, green: 0.251, blue: 0.251, alpha: 1.0) {
        didSet { updateAnnotations() }
    }

    /// The default label text color for the night light preset.
    /// Default value: white
    public var textColorNight: UIColor = .white {
        didSet { updateAnnotations() }
    }

    /// The default label text size in points.
    /// Default value: 16.0
    public var textSize: Double = 16.0 {
        didSet { updateAnnotations() }
    }

    /// The font stack for labels. Uses the first available font from the list.
    /// Default value: ["DIN Pro Medium", "Arial Unicode MS Regular"]
    public var textFont: [String] = ["DIN Pro Medium", "Arial Unicode MS Regular"] {
        didSet { updateTextFont() }
    }

    /// The style slot to place the annotation layers into.
    /// Set this before assigning `annotations` for the slot to take effect.
    public var slot: Slot?

    /// Creates a new building annotation manager.
    ///
    /// - Parameters:
    ///   - mapView: The map view to add annotations to
    ///   - slot: The style slot to place the annotation layers into. Can also be set via the `slot` property before the first `annotations` assignment.
    public init(mapView: MapView, slot: Slot? = nil) {
        self.mapView = mapView
        self.slot = slot

        Self.idGenerator += 1
        let id = Self.idGenerator
        self.sourceId = "building-annotation-source-\(id)"
        self.layerId = "building-annotation-layer-\(id)"
        self.symbolSourceId = "building-annotation-symbol-source-\(id)"
        self.symbolLayerId = "building-annotation-symbol-layer-\(id)"
    }

    private func setupLayer() {
        guard !isInitialized else { return }

        guard mapView.mapboxMap.isStyleLoaded else {
            styleLoadedToken = mapView.mapboxMap.onStyleLoaded.observe { [weak self] _ in
                self?.styleLoadedToken = nil
                self?.setupLayer()
            }
            return
        }

        var source = GeoJSONSource(id: sourceId)
        source.data = .featureCollection(FeatureCollection(features: []))

        var layer = FillExtrusionLayer(id: layerId, source: sourceId)
        layer.fillExtrusionColor = .expression(Exp(.get) { "color" })
        layer.fillExtrusionHeight = .expression(Exp(.get) { "height" })
        layer.fillExtrusionBase = .expression(Exp(.get) { "base" })
        layer.fillExtrusionOpacity = .constant(fillExtrusionOpacity)
        layer.slot = slot

        try? mapView.mapboxMap.addSource(source)
        try? mapView.mapboxMap.addLayer(layer)

        var symbolSource = GeoJSONSource(id: symbolSourceId)
        symbolSource.data = .featureCollection(FeatureCollection(features: []))

        let symbolLayer = makeBuildingSymbolLayer(
            id: symbolLayerId,
            source: symbolSourceId,
            textFont: textFont,
            slot: slot
        )

        try? mapView.mapboxMap.addSource(symbolSource)
        try? mapView.mapboxMap.addLayer(symbolLayer)

        isInitialized = true
        updateAnnotations()
    }

    private func updateAnnotations() {
        setupLayer()
        guard isInitialized else { return }

        let features = annotations.map { createFeature(from: $0) }
        mapView.mapboxMap.updateGeoJSONSource(
            withId: sourceId,
            geoJSON: .featureCollection(FeatureCollection(features: features))
        )

        let symbolFeatures = annotations.compactMap { createSymbolFeature(from: $0) }
        mapView.mapboxMap.updateGeoJSONSource(
            withId: symbolSourceId,
            geoJSON: .featureCollection(FeatureCollection(features: symbolFeatures))
        )
    }

    private func createFeature(from annotation: BuildingAnnotation) -> Feature {
        var feature = Feature(geometry: .polygon(Polygon([annotation.coordinates])))
        feature.properties = [
            "color": .string(StyleColor(annotation.fillExtrusionColor ?? fillExtrusionColor).rawValue),
            "height": .number(annotation.fillExtrusionHeight ?? fillExtrusionHeight),
            "base": .number(annotation.fillExtrusionBase ?? fillExtrusionBase)
        ]
        return feature
    }

    private func createSymbolFeature(from annotation: BuildingAnnotation) -> Feature? {
        annotation.computeLabelFeature(
            fallbackTextColor: textColor,
            fallbackTextColorNight: textColorNight,
            fallbackTextSize: textSize,
            fallbackTextFont: textFont
        )
    }

    private func updateLayerOpacity() {
        guard isInitialized else { return }
        try? mapView.mapboxMap.setLayerProperty(
            for: layerId,
            property: "fill-extrusion-opacity",
            value: fillExtrusionOpacity
        )
    }

    private func updateTextFont() {
        guard isInitialized else { return }
        try? mapView.mapboxMap.setLayerProperty(
            for: symbolLayerId,
            property: "text-font",
            value: textFont
        )
    }
}

extension BuildingAnnotation: Equatable {
    public static func == (lhs: BuildingAnnotation, rhs: BuildingAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}
