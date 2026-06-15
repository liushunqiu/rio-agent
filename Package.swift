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
                ".gitignore",
                "Tests",
                "Resources",
                "project.yml",
                "Rio Agent.app"
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
