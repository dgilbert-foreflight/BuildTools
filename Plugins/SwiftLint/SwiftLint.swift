import PackagePlugin
import Foundation

@main
struct SwiftLint: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard target.sourceModule?.sourceFiles != nil else { return [] }
        if ProcessInfo.processInfo.environment["DISABLE_SWIFTLINT"] != nil { return [] }
        return [
            .buildCommand(
                displayName: "Running SwiftLint for \(target.name)",
                executable: try context.tool(named: "swiftlint").path,
                arguments: [
                    "lint",
                    "--config",
                    "\(context.package.directory.string)/.swiftlint.yml",
                    "--cache-path",
                    "\(context.pluginWorkDirectory.string)/cache",
                    target.directory.string
                ]
            )
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftLint: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        if ProcessInfo.processInfo.environment["DISABLE_SWIFTLINT"] != nil { return [] }
        return [
            .buildCommand(
                displayName: "Running SwiftLint for \(target.displayName)",
                executable: try context.tool(named: "swiftlint").path,
                arguments: [
                    "lint",
                    "--config",
                    "\(context.xcodeProject.directory.string)/.swiftlint.yml",
                    "--cache-path",
                    "\(context.pluginWorkDirectory.string)/cache",
                    context.xcodeProject.directory.string
                ]
            )
        ]
    }
}

#endif
