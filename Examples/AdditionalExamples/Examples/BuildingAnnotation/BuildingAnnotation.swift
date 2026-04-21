/*
 This code example is part of the Mapbox Navigation SDK for iOS demo app,
 which you can build and run: https://github.com/mapbox/mapbox-navigation-ios
 To learn more about the SDK, see our docs: https://docs.mapbox.com/ios/navigation
 */

import CoreLocation
import Foundation
@_spi(Experimental) import MapboxMaps
#if canImport(SwiftUI)
import SwiftUI
#endif
import Turf
import UIKit

/// An annotation representing a 3D building on the map.
///
/// Building annotations are value types that define the visual appearance of a building.
///
/// ## UIKit Usage
/// ```swift
/// let annotation = BuildingAnnotation(
///     coordinates: points,
///     fillExtrusionHeight: 50.0
/// )
///
/// let manager = BuildingAnnotationManager(mapView: mapView)
/// manager.annotations = [annotation]
/// ```
///
/// ## SwiftUI Usage
/// ```swift
/// Map {
///     BuildingAnnotation(coordinates: points)
///         .fillExtrusionHeight(50.0)
///         .fillExtrusionColor(.blue)
///         .labelText("Destination")
/// }
/// ```
public struct BuildingAnnotation {
    public let id: String

    public var coordinates: [CLLocationCoordinate2D]
    public var fillExtrusionColor: UIColor?
    public var fillExtrusionOpacity: Double?
    public var fillExtrusionHeight: Double?
    public var fillExtrusionBase: Double?

    /// Optional text label displayed above the building, elevated to the rooftop.
    public var labelText: String?

    /// When provided, the label is placed near the nearest point on the building boundary
    /// to this coordinate. Falls back to the polygon centroid when nil.
    public var labelPosition: CLLocationCoordinate2D?

    /// Label text color in the day light preset. nil inherits from the manager default or uses #404040.
    public var textColor: UIColor?

    /// Label text color in the night light preset. nil inherits from the manager default or uses white.
    public var textColorNight: UIColor?

    /// Label text size in points. nil inherits from the manager default or uses 16.0.
    public var textSize: Double?

    /// Font stack for the label. nil inherits from the manager default.
    public var textFont: [String]?

    /// The style slot to place the annotation layers into.
    public var slot: Slot?

    /// Creates a new building annotation.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this annotation (default: auto-generated UUID)
    ///   - coordinates: The list of coordinates for the building footprint polygon
    ///   - fillExtrusionColor: The color of the building extrusion (default: nil, inherits from manager)
    ///   - fillExtrusionOpacity: The opacity of the building extrusion (default: nil, inherits from manager)
    ///   - fillExtrusionHeight: The height of the building extrusion in meters (default: nil, inherits from manager)
    ///   - fillExtrusionBase: The base elevation of the building extrusion in meters (default: nil, inherits from manager)
    ///   - labelText: Optional text label to display above the building, elevated to the rooftop
    ///   - labelPosition: When provided, the label is placed near this coordinate on the building boundary
    ///   - textColor: Label text color in day light preset (default: nil, uses #404040)
    ///   - textColorNight: Label text color in night light preset (default: nil, uses white)
    ///   - textSize: Label text size in points (default: nil, uses 16.0)
    ///   - textFont: Font stack for the label (default: nil, uses DIN Pro Medium)
    ///   - slot: The style slot to place the layers into
    public init(
        id: String = UUID().uuidString,
        coordinates: [CLLocationCoordinate2D],
        fillExtrusionColor: UIColor? = nil,
        fillExtrusionOpacity: Double? = nil,
        fillExtrusionHeight: Double? = nil,
        fillExtrusionBase: Double? = nil,
        labelText: String? = nil,
        labelPosition: CLLocationCoordinate2D? = nil,
        textColor: UIColor? = nil,
        textColorNight: UIColor? = nil,
        textSize: Double? = nil,
        textFont: [String]? = nil,
        slot: Slot? = nil
    ) {
        self.id = id
        self.coordinates = coordinates
        self.fillExtrusionColor = fillExtrusionColor
        self.fillExtrusionOpacity = fillExtrusionOpacity
        self.fillExtrusionHeight = fillExtrusionHeight
        self.fillExtrusionBase = fillExtrusionBase
        self.labelText = labelText
        self.labelPosition = labelPosition
        self.textColor = textColor
        self.textColorNight = textColorNight
        self.textSize = textSize
        self.textFont = textFont
        self.slot = slot
    }

    internal var sourceId: String { "building-annotation-source-\(id)" }
    internal var layerId: String { "building-annotation-layer-\(id)" }
    internal var symbolSourceId: String { "building-annotation-symbol-source-\(id)" }
    internal var symbolLayerId: String { "building-annotation-symbol-layer-\(id)" }

    // MARK: - Builder methods

    /// Sets the fill extrusion color.
    public func fillExtrusionColor(_ color: UIColor) -> Self {
        var copy = self; copy.fillExtrusionColor = color; return copy
    }

    /// Sets the fill extrusion opacity.
    public func fillExtrusionOpacity(_ opacity: Double) -> Self {
        var copy = self; copy.fillExtrusionOpacity = opacity; return copy
    }

    /// Sets the fill extrusion height.
    public func fillExtrusionHeight(_ height: Double) -> Self {
        var copy = self; copy.fillExtrusionHeight = height; return copy
    }

    /// Sets the fill extrusion base elevation.
    public func fillExtrusionBase(_ base: Double) -> Self {
        var copy = self; copy.fillExtrusionBase = base; return copy
    }

    /// Sets the label text displayed above the building.
    public func labelText(_ text: String) -> Self {
        var copy = self; copy.labelText = text; return copy
    }

    /// Sets the label position used to anchor the label near a specific point on the building boundary.
    public func labelPosition(_ position: CLLocationCoordinate2D) -> Self {
        var copy = self; copy.labelPosition = position; return copy
    }

    /// Sets the label text color for the day light preset.
    public func textColor(_ color: UIColor) -> Self {
        var copy = self; copy.textColor = color; return copy
    }

    /// Sets the label text color for the night light preset.
    public func textColorNight(_ color: UIColor) -> Self {
        var copy = self; copy.textColorNight = color; return copy
    }

    /// Sets the label text size.
    public func textSize(_ size: Double) -> Self {
        var copy = self; copy.textSize = size; return copy
    }

    /// Sets the font stack for the label.
    public func textFont(_ font: [String]) -> Self {
        var copy = self; copy.textFont = font; return copy
    }

    /// Sets the style slot for the annotation layers.
    public func slot(_ slot: Slot) -> Self {
        var copy = self; copy.slot = slot; return copy
    }

    // MARK: - Internal helpers

    /// Computes a label GeoJSON feature with a 5 m inset from the boundary toward the centroid,
    /// so the label renders inside the polygon.
    internal func computeLabelFeature(
        fallbackTextColor: UIColor,
        fallbackTextColorNight: UIColor,
        fallbackTextSize: Double,
        fallbackTextFont: [String]
    ) -> Feature? {
        guard let labelText = labelText else { return nil }

        let centroid = buildingCentroid(of: coordinates)
        let nearest = labelPosition ?? centroid

        let dx = nearest.longitude - centroid.longitude
        let dy = nearest.latitude - centroid.latitude
        let anchor: String
        if abs(dx) >= abs(dy) {
            anchor = dx > 0 ? "right" : "left"
        } else {
            anchor = dy > 0 ? "top" : "bottom"
        }

        let bearing = nearest.direction(to: centroid)
        let distanceMeters = nearest.distance(to: centroid)
        let insetMeters = distanceMeters * 0.25
        let labelCoordinate = nearest.coordinate(at: insetMeters, facing: bearing)

        var feature = Feature(geometry: .point(Point(labelCoordinate)))
        feature.properties = [
            "label": .string(labelText),
            "textAnchor": .string(anchor),
            "textColorDay": .string(StyleColor(textColor ?? fallbackTextColor).rawValue),
            "textColorNight": .string(StyleColor(textColorNight ?? fallbackTextColorNight).rawValue),
            "textSize": .number(textSize ?? fallbackTextSize)
        ]
        return feature
    }
}

/// Returns the mean-coordinate centroid of a polygon ring.
internal func buildingCentroid(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
    guard !coordinates.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
    let lat = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
    let lng = coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
}

/// Builds a symbol layer for building labels, shared between the standalone and group APIs.
internal func makeBuildingSymbolLayer(id: String, source: String, textFont: [String], slot: Slot?) -> SymbolLayer {
    let textColorExpression = Exp(.interpolate) {
        Exp(.linear)
        Exp(.measureLight) { "brightness" }
        0.25
        Exp(.get) { "textColorNight" }
        0.3
        Exp(.get) { "textColorDay" }
    }
    let textHaloColorExpression = Exp(.interpolate) {
        Exp(.linear)
        Exp(.measureLight) { "brightness" }
        0.25
        "#0D0D0D"
        0.3
        "#FFFFFF"
    }

    var layer = SymbolLayer(id: id, source: source)
    layer.symbolPlacement = .constant(.point)
    layer.symbolZElevate = .constant(true)
    layer.symbolZOrder = .constant(.auto)
    layer.textField = .expression(Exp(.get) { "label" })
    layer.textVariableAnchor = .constant([.top, .bottom, .left, .right])
    layer.textRadialOffset = .constant(0.25)
    layer.textAnchor = .expression(Exp(.get) { "textAnchor" })
    layer.textEmissiveStrength = .constant(1.0)
    layer.textColor = .expression(textColorExpression)
    layer.textHaloColor = .expression(textHaloColorExpression)
    layer.textSize = .expression(Exp(.get) { "textSize" })
    layer.textHaloWidth = .constant(0.5)
    layer.textHaloBlur = .constant(1.0)
    layer.textFont = .constant(textFont)
    layer.slot = slot
    return layer
}

#if canImport(SwiftUI)
@available(iOS 14.0, *)
extension BuildingAnnotation: MapStyleContent {
    public var body: some MapStyleContent {
        let defaultColor = UIColor(red: 0.204, green: 0.537, blue: 0.976, alpha: 1.0)
        let defaultTextColor = UIColor(red: 0.251, green: 0.251, blue: 0.251, alpha: 1.0)
        let effectiveTextFont = textFont ?? ["DIN Pro Medium", "Arial Unicode MS Regular"]

        GeoJSONSource(id: sourceId)
            .data(.geometry(.polygon(Polygon([coordinates]))))

        makeExtrusionLayer(defaultColor: defaultColor)

        if let feature = computeLabelFeature(
            fallbackTextColor: defaultTextColor,
            fallbackTextColorNight: .white,
            fallbackTextSize: 16.0,
            fallbackTextFont: effectiveTextFont
        ) {
            GeoJSONSource(id: symbolSourceId)
                .data(.featureCollection(FeatureCollection(features: [feature])))

            makeBuildingSymbolLayer(id: symbolLayerId, source: symbolSourceId, textFont: effectiveTextFont, slot: slot)
        }
    }

    private func makeExtrusionLayer(defaultColor: UIColor) -> FillExtrusionLayer {
        var layer = FillExtrusionLayer(id: layerId, source: sourceId)
        layer.fillExtrusionColor = .constant(StyleColor(fillExtrusionColor ?? defaultColor))
        layer.fillExtrusionHeight = .constant(fillExtrusionHeight ?? 50.0)
        layer.fillExtrusionBase = .constant(fillExtrusionBase ?? 0.0)
        layer.fillExtrusionOpacity = .constant(fillExtrusionOpacity ?? 0.8)
        layer.slot = slot
        return layer
    }
}
#endif
