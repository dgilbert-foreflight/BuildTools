import PackagePlugin
import Foundation

@main
struct SwiftLintFix: CommandPlugin {
    
    func performCommand(
        context: PackagePlugin.PluginContext,
        arguments: [String]
    ) async throws {
        try context.package
            .targets
            .compactMap { $0 as? SourceModuleTarget }
            .forEach { target in
                try performCommand(
                    inputFiles: target.sourceFiles(withSuffix: "swift").map(\.path),
                    targetDirectory: context.package.directory,
                    workingDirectory: context.pluginWorkDirectory,
                    tool: try context.tool(named: "swiftlint").path
                )
            }
    }
    
    private func performCommand(
        inputFiles: [Path],
        targetDirectory: Path,
        workingDirectory: Path,
        tool: Path
    ) throws {
        guard
            !inputFiles.isEmpty,
            let configuration = targetDirectory.firstConfigurationFileInParentDirectories()
        else {
            Diagnostics.error("swiftlint not setup | nothing to lint")
            return
        }
        
        let process = Process()
        process.executableURL = URL(filePath: tool.string)
        process.arguments = [
            "lint",
            "--fix",
            "--config",
            "\(configuration)",
            "--force-exclude",
            "--cache-path",
            "\(workingDirectory)",
        ]
        
        process.arguments! += inputFiles.map(\.string)
        
        print(
            tool,
            process.arguments?.joined(separator: " ") ?? ""
        )
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationReason == .exit && process.terminationStatus == 0 {
            print("Formatted the source code in \(targetDirectory).")
        } else {
            let problem = "\(process.terminationReason):\(process.terminationStatus)"
            Diagnostics.error("swift-format invocation failed: \(problem)")
        }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftLintFix: XcodeCommandPlugin {
    
    func performCommand(
        context: XcodePluginContext,
        arguments: [String]
    ) throws {
        try context.xcodeProject.targets.forEach { target in
            try performCommand(
                inputFiles: target.sourceFiles(withSuffix: "swift").map(\.path),
                targetDirectory: context.xcodeProject.directory,
                workingDirectory: context.pluginWorkDirectory,
                tool: try context.tool(named: "swiftlint").path
            )
        }
    }
}

extension XcodeTarget {
    
    func sourceFiles(withSuffix suffix: String) -> [FileList.Element] {
        inputFiles.filter { $0.type == .source && $0.path.extension == suffix }
    }
}

#endif

extension Path {
    /// Scans the receiver, then all of its parents looking for a configuration file with the name ".swiftlint.yml".
    ///
    /// - returns: Path to the configuration file, or nil if one cannot be found.
    func firstConfigurationFileInParentDirectories() -> Path? {
        let defaultConfigurationFileName = ".swiftlint.yml"
        let proposedDirectory = sequence(
            first: self,
            next: { path in
                // Check we're not at the root of this filesystem, as `removingLastComponent()`
                // will continually return the root from itself.
                guard path.stem.count > 1 else { return nil }
                return path.removingLastComponent()
            }
        ).first { path in
            let potentialConfigurationFile = path.appending(subpath: defaultConfigurationFileName)
            return potentialConfigurationFile.isAccessible()
        }
        return proposedDirectory?.appending(subpath: defaultConfigurationFileName)
    }
    
    /// Safe way to check if the file is accessible from within the current process sandbox.
    private func isAccessible() -> Bool {
        let result = string.withCString { pointer in
            access(pointer, R_OK)
        }
        
        return result == 0
    }
}
