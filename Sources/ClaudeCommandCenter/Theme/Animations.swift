import SwiftUI

extension Theme {
    enum Animations {
        static let spring        = Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let springBouncy  = Animation.spring(response: 0.35, dampingFraction: 0.65)
        static let springSnappy  = Animation.spring(response: 0.25, dampingFraction: 0.85)
        static let easeOut       = Animation.easeOut(duration: 0.2)
        static let breath        = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)

        static func staggered(index: Int, base: Double = 0.03) -> Animation {
            spring.delay(Double(index) * base)
        }
    }
}
