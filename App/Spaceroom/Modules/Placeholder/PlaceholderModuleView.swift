// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Illustrated page for modules that aren't built yet, so the full menu is visible from day one.
struct PlaceholderModuleView: View {
    let module: SidebarModule

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ModuleHero(module: module, size: 190)
            Text(module.title)
                .font(Typography.hero())
                .padding(.top, 8)
            Text(module.tagline)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 6)
            if let milestone = module.plannedMilestone {
                Pill(text: Text(milestone))
                    .padding(.top, 18)
            }
            Spacer()
            PrimaryCircleButton(title: "Scan", isEnabled: false) {}
                .padding(.bottom, 40)
        }
        .padding(.horizontal, 40)
    }
}
