/*
 This code example is part of the Mapbox Navigation SDK for iOS demo app,
 which you can build and run: https://github.com/mapbox/mapbox-navigation-ios
 To learn more about the SDK, see our docs: https://docs.mapbox.com/ios/navigation
 */

#if canImport(SwiftUI)
import CoreLocation
import Foundation
@_spi(Experimental) import MapboxMaps
import SwiftUI
import Turf

/// Displays a group of building annotations.
///
/// When displaying multiple annotations, `BuildingAnnotationGroup` is more performant than
/// individual annotations since only one underlying source and layer is used.
///
/// The group provides default values for all fill extrusion properties. Individual annotations
/// can override these defaults by specifying their own values.
///
/// **Note:** Due to FillExtrusionLayer limitations, `fillExtrusionOpacity` is applied uniformly
/// to all buildings in the group. Individual annotation opacity values are ignored.
///
/// ## Example Usage
/// ```swift
/// Map {
///     BuildingAnnotationGroup(buildings, id: \.id) { building in
///         BuildingAnnotation(coordinates: building.coordinates)
///             .fillExtrusionHeight(building.height)
///             .labelText(building.name)
///     }
///     .fillExtrusionColor(.green)  // Default color for all
///     .fillExtrusionOpacity(0.9)   // Group-level opacity
///     .slot(.middle)
/// }
/// ```
@available(iOS 14.0, *)
public struct BuildingAnnotationGroup<Data: RandomAccessCollection, ID: Hashable> {
    let annotations: [(ID, BuildingAnnotation)]

    // Group-level property defaults
    private var fillExtrusionColor: UIColor?
    private var fillExtrusionOpacity: Double?
    private var fillExtrusionHeight: Double?
    private var fillExtrusionBase: Double?
    private var textColor: UIColor?
    private var textColorNight: UIColor?
    private var textSize: Double?
    private var textFont: [String]?
    private var slot: Slot?
    private var layerId: String?

    /// Creates a group of building annotations from a data collection.
    public init(
        _ data: Data,
        id: KeyPath<Data.Element, ID>,
        content: @escaping (Data.Element) -> BuildingAnnotation
    ) {
        self.annotations = data.map { element in
            (element[keyPath: id], content(element))
        }
    }

    /// Creates a group of building annotations from identifiable data.
    public init(
        _ data: Data,
        content: @escaping (Data.Element) -> BuildingAnnotation
    ) where Data.Element: Identifiable, Data.Element.ID == ID {
        self.init(data, id: \.id, content: content)
    }

    /// Creates a group with a static list of building annotations.
    public init(
        @ArrayBuilder<BuildingAnnotation> content: () -> [BuildingAnnotation]
    ) where ID == Int {
        self.annotations = Array(content().enumerated())
    }

    // MARK: - Builder methods

    /// Sets the fill extrusion color for all annotations in the group.
    public func fillExtrusionColor(_ color: UIColor) -> Self {
        var copy = self; copy.fillExtrusionColor = color; return copy
    }

    /// Sets the fill extrusion opacity for all annotations in the group.
    ///
    /// This is a layer-level property due to FillExtrusionLayer limitations.
    public func fillExtrusionOpacity(_ opacity: Double) -> Self {
        var copy = self; copy.fillExtrusionOpacity = opacity; return copy
    }

    /// Sets the fill extrusion height for all annotations in the group.
    public func fillExtrusionHeight(_ height: Double) -> Self {
        var copy = self; copy.fillExtrusionHeight = height; return copy
    }

    /// Sets the fill extrusion base for all annotations in the group.
    public func fillExtrusionBase(_ base: Double) -> Self {
        var copy = self; copy.fillExtrusionBase = base; return copy
    }

    /// Sets the default label text color for the day light preset.
    public func textColor(_ color: UIColor) -> Self {
        var copy = self; copy.textColor = color; return copy
    }

    /// Sets the default label text color for the night light preset.
    public func textColorNight(_ color: UIColor) -> Self {
        var copy = self; copy.textColorNight = color; return copy
    }

    /// Sets the default label text size.
    public func textSize(_ size: Double) -> Self {
        var copy = self; copy.textSize = size; return copy
    }

    /// Sets the font stack for labels.
    public func textFont(_ font: [String]) -> Self {
        var copy = self; copy.textFont = font; return copy
    }

    /// Sets the style slot for the annotation layers.
    public func slot(_ slot: Slot) -> Self {
        var copy = self; copy.slot = slot; return copy
    }

    /// Sets the layer ID for the annotation group.
    public func layerId(_ id: String) -> Self {
        var copy = self; copy.layerId = id; return copy
    }

    // MARK: - Feature collection builders

    private func buildFeatureCollection() -> FeatureCollection {
        let defaultColor = UIColor(red: 0.204, green: 0.537, blue: 0.976, alpha: 1.0)

        let features: [Feature] = annotations.map { (_, annotation) in
            let color = annotation.fillExtrusionColor ?? fillExtrusionColor ?? defaultColor
            let height = annotation.fillExtrusionHeight ?? fillExtrusionHeight ?? 50.0
            let base = annotation.fillExtrusionBase ?? fillExtrusionBase ?? 0.0

            var feature = Feature(geometry: .polygon(Polygon([annotation.coordinates])))
            feature.properties = [
                "color": .string(StyleColor(color).rawValue),
                "height": .number(height),
                "base": .number(base)
            ]
            return feature
        }

        return FeatureCollection(features: features)
    }

    private func buildSymbolFeatureCollection() -> FeatureCollection {
        let defaultTextColor = UIColor(red: 0.251, green: 0.251, blue: 0.251, alpha: 1.0)

        let features: [Feature] = annotations.compactMap { (_, annotation) in
            annotation.computeLabelFeature(
                fallbackTextColor: textColor ?? defaultTextColor,
                fallbackTextColorNight: textColorNight ?? .white,
                fallbackTextSize: textSize ?? 16.0,
                fallbackTextFont: textFont ?? ["DIN Pro Medium", "Arial Unicode MS Regular"]
            )
        }

        return FeatureCollection(features: features)
    }
}

@available(iOS 14.0, *)
extension BuildingAnnotationGroup: MapStyleContent {
    public var body: some MapStyleContent {
        let sourceId = layerId ?? "building-annotation-group-source"
        let extrusionLayerId = layerId ?? "building-annotation-group-layer"
        let symbolSourceId = (layerId ?? "building-annotation-group") + "-symbol-source"
        let symbolLayerId = (layerId ?? "building-annotation-group") + "-symbol-layer"
        let effectiveTextFont = textFont ?? ["DIN Pro Medium", "Arial Unicode MS Regular"]

        let featureCollection = buildFeatureCollection()
        let symbolFeatureCollection = buildSymbolFeatureCollection()

        GeoJSONSource(id: sourceId)
            .data(.featureCollection(featureCollection))

        makeExtrusionLayer(id: extrusionLayerId, source: sourceId)

        if !symbolFeatureCollection.features.isEmpty {
            GeoJSONSource(id: symbolSourceId)
                .data(.featureCollection(symbolFeatureCollection))

            makeBuildingSymbolLayer(id: symbolLayerId, source: symbolSourceId, textFont: effectiveTextFont, slot: slot)
        }
    }

    private func makeExtrusionLayer(id: String, source: String) -> FillExtrusionLayer {
        var layer = FillExtrusionLayer(id: id, source: source)
        layer.fillExtrusionColor = .expression(Exp(.get) { "color" })
        layer.fillExtrusionHeight = .expression(Exp(.get) { "height" })
        layer.fillExtrusionBase = .expression(Exp(.get) { "base" })
        layer.fillExtrusionOpacity = .constant(fillExtrusionOpacity ?? 0.8)
        layer.slot = slot
        return layer
    }
}

#endif
