// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "RioAgent",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "RioAgent",
            targets: ["RioAgent"]
        )
    ],
    targets: [
        .executableTarget(
            name: "RioAgent",
            dependencies: [],
            path: ".",
            exclude: [
                "Package.swift",
                "Info.plist",
                "build.sh",
                "create_app.sh",
                "run.sh",
                "README.md",
                "AGENT.md",
                "CLAUDE.md",
                ".gitignore",
                "Tests",
                "Resources",
                "project.yml",
                "Rio Agent.app",
                "Optimizations",
                "OPTIMIZATION_ANALYSIS.md",
                "OPTIMIZATION_RECOMMENDATIONS.md",
                "QUICK_REFERENCE.md",
                "PHASE2_OPTIMIZATION.md",
                "PHASE3_OPTIMIZATION.md",
                "PHASE4_OPTIMIZATION.md",
                "PIPELINE_IMPROVEMENTS.md",
                "INTEGRATION_COMPLETE.md",
                "TOKENTRACKER_INTEGRATION.md",
                "RioAgent.entitlements"
            ],
            sources: [
                "App",
                "Views",
                "ViewModels",
                "Agent",
                "Services",
                "Tools",
                "Models",
                "Utils",
                "Theme"
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "RioAgentTests",
            dependencies: ["RioAgent"],
            path: "Tests"
        )
    ]
)
