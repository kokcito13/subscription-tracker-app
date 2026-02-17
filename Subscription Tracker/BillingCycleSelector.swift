//
//  BillingCycleSelector.swift
//  Subscription Tracker
//
//  Created by GitHub Copilot on 17.02.2026.
//

import SwiftUI

/// Card-based selector for billing cycles displayed in an HStack
struct BillingCycleSelector: View {
    @Binding var selectedCycle: BillingCycle
    
    static let cardHeight: CGFloat = 60
    
    var body: some View {
        GeometryReader { geometry in
            // Use VStack on very narrow screens (< 300px), otherwise HStack
            if geometry.size.width < 300 {
                VStack(spacing: 16) {
                    ForEach(BillingCycle.allCases) { cycle in
                        CycleCard(
                            cycle: cycle,
                            isSelected: selectedCycle == cycle,
                            action: { selectedCycle = cycle }
                        )
                    }
                }
            } else {
                HStack(spacing: 16) {
                    ForEach(BillingCycle.allCases) { cycle in
                        CycleCard(
                            cycle: cycle,
                            isSelected: selectedCycle == cycle,
                            action: { selectedCycle = cycle }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(height: BillingCycleSelector.cardHeight)
    }
}

struct CycleCard: View {
    let cycle: BillingCycle
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(cycle.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(periodDescription(for: cycle))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: BillingCycleSelector.cardHeight)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.blue : Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.blue.opacity(0.5) : Color.gray.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func periodDescription(for cycle: BillingCycle) -> String {
        switch cycle {
        case .weekly:
            return "Every week"
        case .monthly:
            return "Every month"
        case .yearly:
            return "Every year"
        }
    }
}

#Preview {
    VStack {
        BillingCycleSelector(selectedCycle: .constant(.monthly))
            .frame(height: BillingCycleSelector.cardHeight)
            .padding()
        
        Spacer()
    }
}
