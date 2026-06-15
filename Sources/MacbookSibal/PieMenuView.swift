import SwiftUI

struct SectorShape: Shape {
    var startAngle: Double // clockwise degrees from North
    var endAngle: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        
        let startAngleSwiftUI = Angle(degrees: startAngle - 90)
        let endAngleSwiftUI = Angle(degrees: endAngle - 90)
        
        let endRad = endAngleSwiftUI.radians
        
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngleSwiftUI,
            endAngle: endAngleSwiftUI,
            clockwise: false
        )
        
        let innerEndX = center.x + innerRadius * cos(endRad)
        let innerEndY = center.y + innerRadius * sin(endRad)
        path.addLine(to: CGPoint(x: innerEndX, y: innerEndY))
        
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngleSwiftUI,
            endAngle: startAngleSwiftUI,
            clockwise: true
        )
        
        path.closeSubpath()
        return path
    }
}

public struct PieMenuView: View {
    @ObservedObject var configManager = ConfigManager.shared
    
    // Mouse offset relative to initial position (Cocoa coords: positive Y is up)
    var mouseOffset: NSSize
    
    @State private var hoveredSectorIndex: Int? = nil
    
    private var outerRadius: CGFloat { configManager.config.menuRadius }
    private var innerRadius: CGFloat { outerRadius * 0.34375 } // proportional to 55/160
    private var cancelRadius: CGFloat { outerRadius * 0.28125 } // proportional to 45/160
    
    private var themeColor: Color { Color(hex: configManager.activeProfile.themeColorHex) }
    
    public init(mouseOffset: NSSize) {
        self.mouseOffset = mouseOffset
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let sectors = configManager.activeProfile.sectors
            let N = sectors.count > 0 ? sectors.count : 1
            let sectorWidth = 360.0 / Double(N)
            
            ZStack {
                // Background shadow for the whole circle
                Circle()
                    .fill(Color.black.opacity(0.15))
                    .frame(width: outerRadius * 2, height: outerRadius * 2)
                    .blur(radius: 12)
                
                // Draw each sector
                ForEach(0..<N, id: \.self) { i in
                    let sector = sectors[i]
                    let startAngle = Double(i) * sectorWidth
                    let endAngle = startAngle + sectorWidth
                    let midAngle = startAngle + sectorWidth / 2
                    
                    let isHovered = (hoveredSectorIndex == i)
                    
                    // Offset for hover micro-animation
                    let offsetDistance: CGFloat = isHovered ? 8 : 0
                    let rad = (midAngle - 90) * .pi / 180.0
                    let offsetX = offsetDistance * cos(rad)
                    let offsetY = offsetDistance * sin(rad)
                    
                    ZStack {
                        // Sector shape
                        SectorShape(
                            startAngle: startAngle,
                            endAngle: endAngle,
                            innerRadius: innerRadius,
                            outerRadius: outerRadius
                        )
                        .fill(
                            isHovered
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [themeColor.opacity(0.8), themeColor],
                                    startPoint: .center,
                                    endPoint: .topLeading
                                )
                            )
                            : AnyShapeStyle(
                                Color.black.opacity(0.65)
                            )
                        )
                        .overlay(
                            SectorShape(
                                startAngle: startAngle,
                                endAngle: endAngle,
                                innerRadius: innerRadius,
                                outerRadius: outerRadius
                            )
                            .stroke(
                                isHovered
                                ? themeColor.opacity(0.6)
                                : Color.white.opacity(0.15),
                                lineWidth: 1.5
                            )
                        )
                        .shadow(
                            color: isHovered ? themeColor.opacity(0.4) : Color.clear,
                            radius: 10,
                            x: 0,
                            y: 0
                        )
                        
                        // Text label positioned at center of sector
                        let textRadius = (innerRadius + outerRadius) / 2
                        let textX = center.x + textRadius * cos(rad) + offsetX
                        let textY = center.y + textRadius * sin(rad) + offsetY
                        
                        VStack(spacing: 2) {
                            Text(sector.name)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            // Shortened command preview
                            Text(commandPreview(sector.command))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                                .frame(width: 80)
                        }
                        .position(x: textX, y: textY)
                    }
                    .offset(x: offsetX, y: offsetY)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6, blendDuration: 0), value: isHovered)
                }
                
                // Central Cancel Button / Close area
                ZStack {
                    Circle()
                        .fill(
                            hoveredSectorIndex == nil
                            ? AnyShapeStyle(Color.red.opacity(0.85))
                            : AnyShapeStyle(Color.black.opacity(0.85))
                        )
                        .frame(width: innerRadius * 2 - 10, height: innerRadius * 2 - 10)
                        .overlay(
                            Circle()
                                .stroke(
                                    hoveredSectorIndex == nil
                                    ? Color.red
                                    : Color.white.opacity(0.25),
                                    lineWidth: 2
                                )
                        )
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                .shadow(
                    color: hoveredSectorIndex == nil ? Color.red.opacity(0.4) : Color.clear,
                    radius: 8,
                    x: 0,
                    y: 0
                )
                .animation(.easeInOut(duration: 0.15), value: hoveredSectorIndex)
            }
            .position(center)
            .onChange(of: mouseOffset) {
                updateSelection()
            }
        }
        .frame(width: outerRadius * 2 + 50, height: outerRadius * 2 + 50)
    }
    
    private func updateSelection() {
        let dx = mouseOffset.width
        let dy = mouseOffset.height // Cocoa coord (positive is up)
        
        let distance = sqrt(dx * dx + dy * dy)
        
        if distance < cancelRadius {
            setHoveredIndex(nil)
            return
        }
        
        let angle = atan2(dy, dx) // -pi to pi
        var degrees = angle * 180.0 / .pi
        if degrees < 0 {
            degrees += 360.0
        }
        
        // Convert to clockwise from North (0 is North)
        var clockDegrees = 90.0 - degrees
        if clockDegrees < 0 {
            clockDegrees += 360.0
        }
        
        let sectors = configManager.activeProfile.sectors
        let N = sectors.count
        guard N > 0 else {
            setHoveredIndex(nil)
            return
        }
        
        let sectorWidth = 360.0 / Double(N)
        let index = Int(clockDegrees / sectorWidth) % N
        setHoveredIndex(index)
    }
    
    private func setHoveredIndex(_ index: Int?) {
        if hoveredSectorIndex != index {
            hoveredSectorIndex = index
            // Trigger tick feedback when changing highlighted sector
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
    
    private func commandPreview(_ cmd: String) -> String {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 15 {
            return String(trimmed.prefix(12)) + "..."
        }
        return trimmed
    }
}
