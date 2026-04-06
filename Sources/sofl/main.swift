import ArgumentParser

// Use ParsableCommand (not Async) so `run` subcommand executes on main thread
struct Sofl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sofl",
        abstract: "Local speech-to-text daemon powered by parakeet CoreML",
        version: "1.0.0",
        subcommands: [Run.self, Service.self, Test.self, Devices.self, ShowConfig.self]
    )
}

Sofl.main()
