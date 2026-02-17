//
//  SpendingSummaryCard.swift
//  Subscription Tracker
//
//  Created by GitHub Copilot on 17.02.2026.
//

import SwiftUI

/// Variant for spending summary card styling
enum SpendingSummaryVariant {
    case monthly
    case yearly
    
    var iconContainerColor: Color {
        switch self {
        case .monthly:
            return Color.yellow.opacity(0.15)
        case .yearly:
            return Color.green.opacity(0.15)
        }
    }
    
    var iconTintColor: Color {
        switch self {
        case .monthly:
            return Color.yellow.opacity(0.8)
        case .yearly:
            return Color.green.opacity(0.8)
        }
    }
    
    var iconBorderColor: Color {
        switch self {
        case .monthly:
            return Color.yellow.opacity(0.3)
        case .yearly:
            return Color.green.opacity(0.3)
        }
    }
}

/// Reusable spending summary card component following exact design specifications
struct SpendingSummaryCard: View {
    let title: String
    let value: String
    let secondaryValue: String
    let icon: String
    let variant: SpendingSummaryVariant
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: icon + title
            HStack(spacing: 10) {
                // Circular icon container (34px)
                ZStack {
                    Circle()
                        .fill(variant.iconContainerColor)
                        .overlay(
                            Circle()
                                .strokeBorder(variant.iconBorderColor, lineWidth: 1)
                        )
                        .frame(width: 34, height: 34)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(variant.iconTintColor)
                }
                
                // Title text
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 107/255, green: 114/255, blue: 128/255)) // #6B7280
                
                Spacer()
            }
            .padding(.bottom, 8)
            
            // Main value (large, prominent)
            Text(value)
                .font(.system(size: 23, weight: .bold))
                .foregroundColor(Color(red: 17/255, green: 24/255, blue: 39/255)) // #111827
                .padding(.bottom, 6)
            
            // Secondary value (small, muted)
            Text(secondaryValue)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 156/255, green: 163/255, blue: 175/255)) // #9CA3AF
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.65))
                .background(.ultraThinMaterial.opacity(0.5))
                .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Container view for two spending summary cards laid out horizontally
struct SpendingSummaryCards: View {
    let monthly: String
    let yearly: String
    
    var body: some View {
        GeometryReader { geometry in
            // Stack vertically on very small screens (< 360px)
            if geometry.size.width < 360 {
                VStack(spacing: 16) {
                    SpendingSummaryCard(
                        title: "Monthly Spending",
                        value: monthly,
                        secondaryValue: "Per month",
                        icon: "sun.max.fill",
                        variant: .monthly
                    )
                    
                    SpendingSummaryCard(
                        title: "Yearly Spending",
                        value: yearly,
                        secondaryValue: "Total per year",
                        icon: "calendar",
                        variant: .yearly
                    )
                }
            } else {
                // Horizontal layout for normal screens
                HStack(spacing: 16) {
                    SpendingSummaryCard(
                        title: "Monthly Spending",
                        value: monthly,
                        secondaryValue: "Per month",
                        icon: "sun.max.fill",
                        variant: .monthly
                    )
                    .frame(width: (geometry.size.width - 16) / 2)
                    
                    SpendingSummaryCard(
                        title: "Yearly Spending",
                        value: yearly,
                        secondaryValue: "Total per year",
                        icon: "calendar",
                        variant: .yearly
                    )
                    .frame(width: (geometry.size.width - 16) / 2)
                }
            }
        }
        .frame(height: 130) // Fixed height to prevent layout jumps
    }
}

#Preview {
    VStack(spacing: 20) {
        SpendingSummaryCards(monthly: "CHF 42.17", yearly: "CHF 506.04")
            .padding(.horizontal, 20)
        
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.gray.opacity(0.1))
}
