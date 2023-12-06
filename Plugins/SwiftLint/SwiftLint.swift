import PackagePlugin
import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main
struct SwiftLint: BuildToolPlugin {
    
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        guard 
            let sourceTarget = target as? SourceModuleTarget,
            ProcessInfo.processInfo.environment["DISABLE_SWIFTLINT"] == nil
        else { return [] }
        
        return createBuildCommands(
            inputFiles: sourceTarget.sourceFiles(withSuffix: "swift").map(\.path),
            packageDirectory: context.package.directory,
            workingDirectory: context.pluginWorkDirectory,
            tool: try context.tool(named: "swiftlint")
        )
    }
    
    private func createBuildCommands(
        inputFiles: [Path],
        packageDirectory: Path,
        workingDirectory: Path,
        tool: PluginContext.Tool
    ) -> [Command] {
        // Manually look for configuration files, to avoid issues when
        // the plugin does not execute our tool from the package source directory.
        guard
            !inputFiles.isEmpty,
            let configuration = packageDirectory.firstConfigurationFileInParentDirectories()
        else { return [] }
        
        var arguments = [
            "lint",
            "--config",
            "\(configuration)",
            // We always pass all of the Swift source files in the target to the tool,
            // so we need to ensure that any exclusion rules in the configuration are
            // respected.
            "--force-exclude",
        ]
        
        if ProcessInfo.processInfo.environment["isCI"] == "TRUE" {
            arguments.append("--no-cache")
        } else {
            arguments.append(contentsOf: [
                "--cache-path",
                "\(workingDirectory)"
            ])
        }
        arguments += inputFiles.map(\.string)
        
        // We are not producing output files.
        // This is needed only to not include cache files into bundle.
        let outputFilesDirectory = workingDirectory.appending("Output")
        
        return [
            .prebuildCommand(
                displayName: "SwiftLint",
                executable: tool.path,
                arguments: arguments,
                environment: [:],
                outputFilesDirectory: outputFilesDirectory
            )
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftLint: XcodeBuildToolPlugin {
    
    func createBuildCommands(
        context: XcodePluginContext,
        target: XcodeTarget
    ) throws -> [Command] {
        guard
            ProcessInfo.processInfo.environment["DISABLE_SWIFTLINT"] == nil
        else { return [] }
        
        return createBuildCommands(
            inputFiles: target.sourceFiles(withSuffix: "swift").map(\.path),
            packageDirectory: context.xcodeProject.directory,
            workingDirectory: context.pluginWorkDirectory,
            tool: try context.tool(named: "swiftlint")
        )
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
